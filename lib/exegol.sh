#!/usr/bin/env bash
# ─── lib/exegol.sh ─── Exegol container and tmux helpers ──

# ── Exegol helpers ───────────────────────────────────────
__exegol_ensure_running() {
    local target="${1}"
    local ws_root="${2:-${WORKSPACE_ROOT}}"
    local container="${EXEGOL_CONTAINER:-exegol}"

    # Already running? Check mount and return
    if docker ps --filter "name=^${container}$" --format '{{.Names}}' 2>/dev/null | grep -q .; then
        local mount_src
        mount_src=$(docker inspect "$container" --format '{{range .Mounts}}{{if eq .Destination "/workspace"}}{{.Source}}{{end}}{{end}}' 2>/dev/null || echo "")
        if [[ -n "$mount_src" ]] && [[ "$mount_src" = "${ws_root}" ]]; then
            return 0
        fi
    fi

    # Container exists (running or stopped)? Start it — fast
    if docker ps -a --filter "name=^${container}$" --format '{{.Names}}' 2>/dev/null | grep -q .; then
        # Stop if running with wrong mount
        if docker ps --filter "name=^${container}$" --format '{{.Names}}' 2>/dev/null | grep -q .; then
            docker stop "$container" >/dev/null 2>&1
        fi
        # Recreate with correct mount if needed
        local mount_src
        mount_src=$(docker inspect "$container" --format '{{range .Mounts}}{{if eq .Destination "/workspace"}}{{.Source}}{{end}}{{end}}' 2>/dev/null || echo "")
        if [[ -z "$mount_src" ]] || [[ "$mount_src" != "${ws_root}" ]]; then
            docker rm "$container" >/dev/null 2>&1
            if command -v exegol &>/dev/null; then
                exegol start -w "${ws_root}" "$container" &>/dev/null &
            else
                docker run -d --name "$container" -v "${ws_root}:/workspace" --network host "nwodtuhs/exegol:free" sleep infinity
            fi
        else
            docker start "$container" >/dev/null 2>&1
        fi
        return 0
    fi

    # Container doesn't exist — start in background (may take time)
    printf '%b\n' "  ${DIM}Exegol first launch (pulling image)...${RESET}"
    if command -v exegol &>/dev/null; then
        exegol start -w "${ws_root}" "$container" &>/dev/null &
    else
        docker run -d --name "$container" \
            -v "${ws_root}:/workspace" \
            -v /var/run/docker.sock:/var/run/docker.sock \
            --network host \
            "nwodtuhs/exegol:free" sleep infinity
    fi
}

__exegol_tmux_spawn() {
    local container="${1}"
    local session_name="${2}"
    local load_cmd="${3:-}"

    # Wait for container to be ready (up to 120s for first pull)
    printf '%b\n' "  ${DIM}Waiting for Exegol container...${RESET}"
    local waited=0
    while ! docker exec "$container" true 2>/dev/null && [[ $waited -lt 120 ]]; do
        sleep 3; ((waited+=3))
        printf '.' >&2
    done
    echo ""
    if ! docker exec "$container" true 2>/dev/null; then
        printf '%b\n' "  ${YELLOW}[!]${RESET} ${DIM}Exegol not ready after 2min — tmux will be created later${RESET}" >&2
        printf '%b\n' "  ${DIM}Run${RESET} ${YELLOW}dotsec tmux attach${RESET} ${DIM}once container is up${RESET}" >&2
        return 0
    fi

    # Kill existing session
    docker exec "$container" tmux kill-session -t "$session_name" 2>/dev/null || true

    # Create 6-window detached session
    docker exec "$container" tmux new-session -d -s "$session_name" -n recon
    docker exec "$container" tmux new-window  -t "$session_name" -n scan
    docker exec "$container" tmux new-window  -t "$session_name" -n exploit
    docker exec "$container" tmux new-window  -t "$session_name" -n post
    docker exec "$container" tmux new-window  -t "$session_name" -n report
    docker exec "$container" tmux new-window  -t "$session_name" -n monitor

    # Source .env in all windows
    if [[ -n "$load_cmd" ]]; then
        for w in recon scan exploit post report monitor; do
            docker exec "$container" tmux send-keys -t "${session_name}:${w}" "${load_cmd}" Enter
        done
    fi

    # Style
    docker exec "$container" tmux set-option -t "$session_name" status-right "#[fg=cyan]${session_name}#[default] | %H:%M"
    docker exec "$container" tmux set-option -t "$session_name" status-style "bg=#1a1a2e,fg=#e0e0e0"
    docker exec "$container" tmux set-option -t "$session_name" window-status-current-style "bg=#14a3a8,fg=#0d1117,bold"
}

# ── Exegol ───────────────────────────────────────────────
cmd_exegol() {
    local action="${1:-shell}"; shift || true
    local container="${EXEGOL_CONTAINER:-exegol}"

    __require_docker

    local docker_tty=""
    [[ -t 0 ]] && docker_tty="-it"

    case "$action" in
        exec)
            docker exec ${docker_tty} "$container" "$@"
            ;;
        shell)
            docker exec ${docker_tty} "$container" zsh
            ;;
        setup)
            printf '%b\n' "${DIM}Running Exegol tool setup (uv + pnpm)...${RESET}"
            if ! docker ps --filter "name=^${container}$" --format '{{.Names}}' | grep -q .; then
                printf '%b\n' "${YELLOW}[!]${RESET} ${DIM}Container${RESET} ${YELLOW}${container}${RESET} ${DIM}not running.${RESET}" >&2
                printf '%b\n' "  ${DIM}Start it with:${RESET} ${YELLOW}exegol start ${container}${RESET}" >&2
                exit 1
            fi
            docker exec ${docker_tty} "$container" bash /opt/resources/dotenv-sec/setup.sh
            ;;
        *)
            printf '%b\n' "${RED}[!] Usage: dotsec exegol exec|shell|setup${RESET}" >&2
            exit 1
            ;;
    esac
}

# ── Spawn ─────────────────────────────────────────────────
# Instant pentest-ready tmux session, with or without engagement loaded
cmd_spawn() {
    local session_name="${1:-${TARGET:-pentest}}"
    local ws="${WORKSPACE:-}"
    local envfile="${ws}/.env"
    local container="${EXEGOL_CONTAINER:-exegol}"

    __require_docker

    # Check if target is an engagement with .env → use Exegol path
    local exegol_env=""
    [[ -n "$ws" ]] && [[ -f "$envfile" ]] && exegol_env="/workspace/${TARGET:-${session_name}}/.env"

    printf '%b\n' "${DIM}Spawning tmux session in Exegol:${RESET} ${CYAN}${session_name}${RESET}"

    # Ensure Exegol is running
    __exegol_ensure_running "${TARGET:-${session_name}}"

    local load_cmd=""
    [[ -n "$exegol_env" ]] && load_cmd="source ${exegol_env}; clear"

    __exegol_tmux_spawn "$container" "$session_name" "$load_cmd"

    [[ -n "$load_cmd" ]] && printf '%b\n' "  ${GREEN}env${RESET} ${DIM}loaded →${RESET} ${DIM}${exegol_env}${RESET}"

    docker exec -it "$container" tmux attach -t "$session_name"
}

# ── Tmux ─────────────────────────────────────────────────
cmd_tmux() {
    local action="${1:-}"; shift || true
    local target="${TARGET:-}"
    [[ -z "$target" ]] && target="${1:-}"
    local container="${EXEGOL_CONTAINER:-exegol}"

    __require_docker

    case "$action" in
        attach|a)
            [[ -z "$target" ]] && { printf '%b\n' "${RED}[!] No target. dotsec load <target> first${RESET}" >&2; exit 1; }
            docker exec -it "$container" tmux attach -t "$target"
            ;;
        create)
            [[ -z "$target" ]] && { printf '%b\n' "${RED}[!] Usage: dotsec tmux create <target>${RESET}" >&2; exit 1; }
            __exegol_ensure_running "$target"
            __exegol_tmux_spawn "$container" "$target"
            printf '%b\n' "${GREEN}Session${RESET} ${CYAN}${target}${RESET} ${DIM}created in Exegol${RESET}"
            ;;
        kill|k)
            [[ -z "$target" ]] && { printf '%b\n' "${RED}[!] Usage: dotsec tmux kill <target>${RESET}" >&2; exit 1; }
            docker exec "$container" tmux kill-session -t "$target" 2>/dev/null || true
            printf '%b\n' "${DIM}Session${RESET} ${CYAN}${target}${RESET} ${DIM}killed${RESET}"
            ;;
        ls|list)
            docker exec "$container" tmux ls 2>/dev/null || echo "No sessions"
            ;;
        *)
            printf '%b\n' "${RED}[!] Usage: dotsec tmux attach|create|kill|ls${RESET}" >&2
            ;;
    esac
}
