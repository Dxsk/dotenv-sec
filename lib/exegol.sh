#!/usr/bin/env bash
# ─── lib/exegol.sh ─── Exegol container and tmux helpers ──

# Per-engagement Exegol container name. EXEGOL_CONTAINER overrides it (use an
# already-running container instead of creating exegol-<target>).
__exegol_name() {
    echo "${EXEGOL_CONTAINER:-exegol-${1}}"
}

# __exegol_ensure_running <target> [engagement_workspace]
# Create the per-engagement Exegol container (exegol-<target>) with the
# engagement workspace mounted as /workspace and my-resources deployed, or just
# start it if it already exists. Best-effort: returns non-zero only if it can't
# bring the container up.
__exegol_ensure_running() {
    local target="${1}"
    local ws="${2:-${WORKSPACE_ROOT}/${target}}"
    local container; container="$(__exegol_name "$target")"

    # Already running?
    if docker ps --filter "name=^${container}$" --format '{{.Names}}' 2>/dev/null | grep -q .; then
        return 0
    fi
    # Exists but stopped → start it.
    if docker ps -a --filter "name=^${container}$" --format '{{.Names}}' 2>/dev/null | grep -q .; then
        docker start "$container" >/dev/null 2>&1 || true
        return 0
    fi
    # A forced EXEGOL_CONTAINER that doesn't exist: don't try to create it.
    if [[ -n "${EXEGOL_CONTAINER:-}" ]]; then
        printf '%b\n' "  ${YELLOW}[!]${RESET} ${DIM}EXEGOL_CONTAINER=${EXEGOL_CONTAINER} not found — start it yourself${RESET}" >&2
        return 1
    fi
    # Create it. Prefer the exegol CLI: it deploys my-resources and mounts the
    # workspace. stdin=/dev/null makes the post-create auto-attach fail cleanly
    # and leaves the container running detached (we connect via tmux instead).
    if command -v exegol >/dev/null 2>&1; then
        printf '%b\n' "  ${DIM}Creating Exegol container ${container} (first run can take a moment)...${RESET}"
        exegol start "${target}" "${EXEGOL_IMAGE:-free}" -w "${ws}" --accept-eula </dev/null >/dev/null 2>&1 || true
    else
        printf '%b\n' "  ${DIM}exegol CLI not found — using docker run fallback...${RESET}"
        docker run -d --name "$container" \
            -v "${ws}:/workspace" \
            -v "${HOME}/.exegol/my-resources:/opt/my-resources" \
            --network host \
            nwodtuhs/exegol:free sleep infinity >/dev/null 2>&1 || true
    fi
    if docker ps --filter "name=^${container}$" --format '{{.Names}}' 2>/dev/null | grep -q .; then
        return 0
    fi
    printf '%b\n' "  ${YELLOW}[!]${RESET} ${DIM}Exegol container ${container} did not come up${RESET}" >&2
    return 1
}

__exegol_tmux_spawn() {
    local container="${1}"
    local session_name="${2}"
    local load_cmd="${3:-}"

    # Container not present at all → skip without the long wait.
    if ! docker ps -a --filter "name=^${container}$" --format '{{.Names}}' 2>/dev/null | grep -q .; then
        printf '%b\n' "  ${YELLOW}[!]${RESET} ${DIM}No Exegol container ${container} — run${RESET} ${YELLOW}dotsec tmux create ${session_name}${RESET} ${DIM}once it's up${RESET}" >&2
        return 0
    fi

    # Wait for it to be exec-able (short: it was just created/started).
    printf '%b\n' "  ${DIM}Waiting for Exegol container...${RESET}"
    local waited=0
    while ! docker exec "$container" true 2>/dev/null && [[ $waited -lt 60 ]]; do
        sleep 2; ((waited+=2)) || true
        printf '.' >&2
    done
    echo "" >&2
    if ! docker exec "$container" true 2>/dev/null; then
        printf '%b\n' "  ${YELLOW}[!]${RESET} ${DIM}Exegol not ready — ${RESET}${YELLOW}dotsec tmux create ${session_name}${RESET}" >&2
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
    local target="${TARGET:-}"
    local container; container="$(__exegol_name "$target")"

    __require_docker

    if [[ -z "${EXEGOL_CONTAINER:-}" && -z "$target" ]]; then
        printf '%b\n' "${RED}[!] No engagement loaded — ${RESET}${YELLOW}dotsec load <target>${RESET} ${DIM}first${RESET}" >&2
        exit 1
    fi

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
                exit 1
            fi
            docker exec ${docker_tty} "$container" bash /opt/my-resources/setup/load_user_setup.sh
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
    local target="${TARGET:-${session_name}}"
    local ws="${WORKSPACE:-${WORKSPACE_ROOT}/${target}}"
    local envfile="${ws}/.env"
    local container; container="$(__exegol_name "$target")"

    __require_docker

    # Engagement with .env → source it inside (workspace is mounted at /workspace)
    local exegol_env=""
    [[ -f "$envfile" ]] && exegol_env="/workspace/.env"

    printf '%b\n' "${DIM}Spawning tmux session in Exegol:${RESET} ${CYAN}${session_name}${RESET}"

    __exegol_ensure_running "$target" "$ws" || true

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
    local container; container="$(__exegol_name "$target")"

    __require_docker

    case "$action" in
        attach|a)
            [[ -z "$target" ]] && { printf '%b\n' "${RED}[!] No target. dotsec load <target> first${RESET}" >&2; exit 1; }
            docker exec -it "$container" tmux attach -t "$target"
            ;;
        create)
            [[ -z "$target" ]] && { printf '%b\n' "${RED}[!] Usage: dotsec tmux create <target>${RESET}" >&2; exit 1; }
            __exegol_ensure_running "$target" "${WORKSPACE_ROOT}/${target}" || true
            local load_cmd="source /workspace/.env 2>/dev/null; [ -f /workspace/.env.secrets ] && source /workspace/.env.secrets; export TARGET=${target}; clear"
            __exegol_tmux_spawn "$container" "$target" "$load_cmd"
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
