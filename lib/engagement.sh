#!/usr/bin/env bash
# ─── lib/engagement.sh ─── engagement lifecycle commands ──

# ── Engagement commands ─────────────────────────────────
cmd_new() {
    local ws_root="${WORKSPACE_ROOT}"
    local target=""
    local domain=""

    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -w|--workspace)
                ws_root="${2}"; shift 2 ;;
            -w=*|--workspace=*)
                ws_root="${1#*=}"; shift ;;
            --)
                shift; break ;;
            -*)
                printf '%b\n' "${RED}[!] Unknown flag: $1${RESET}" >&2; exit 1 ;;
            *)
                if [[ -z "$target" ]]; then
                    target="$1"
                elif [[ -z "$domain" ]]; then
                    domain="$1"
                fi
                shift ;;
        esac
    done

    __require_docker

    if [[ -z "$target" ]]; then
        printf '%b\n' "${RED}[!] Usage: dotsec new [-w <workspace_root>] <target> [domain]${RESET}" >&2
        exit 1
    fi

    [[ -z "$domain" ]] && domain="${target}"
    local ws="${ws_root}/${target}"

    printf '%b\n' "${BOLD}${GREEN}▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀${RESET}"
    printf '%b\n' "  ${BOLD}${CYAN}New Engagement${RESET}  ${GREEN}▸${RESET} ${BOLD}${target}${RESET}  ${DIM}${domain}${RESET}"
    printf '%b\n' "${BOLD}${GREEN}▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀${RESET}"

    # 1. Workspace structure
    printf '%b\n' "  ${DIM}[1/6]${RESET} ${DIM}Creating workspace...${RESET}"
    mkdir -p "${ws}"/{recon/{passive,active},scans/{ports,web,vuln},exploits/{pocs,payloads},loot/{credentials,data},logs,report/assets,replays/{recon,scan,exploit,post,report,monitor},keys}

    # 2. Copy and fill .env
    printf '%b\n' "  ${DIM}[2/6]${RESET} ${DIM}Setting up dotenv...${RESET}"
    cp "${DOTSEC_HOME}/templates/.env.engagement" "${ws}/.env"
    sed -i "s|WORKSPACE=\"/workspace/acme-corp\"|WORKSPACE=\"${ws}\"|" "${ws}/.env"
    sed -i "s|TARGET=\"acme-corp\"|TARGET=\"${target}\"|" "${ws}/.env"
    sed -i "s|DOMAIN=\"acme-corp.com\"|DOMAIN=\"${domain}\"|" "${ws}/.env"

    # Merge global config defaults (only if key not already set)
    __dotsec_load_global
    [[ -n "${UA:-}" ]] && sed -i "s|H1-yourhandle|${UA}|g" "${ws}/.env"
    [[ -n "${PROXY_PORT:-}" ]] && sed -i "s|PROXY_PORT=\"9999\"|PROXY_PORT=\"${PROXY_PORT}\"|g" "${ws}/.env"
    [[ -n "${WEB_PORT:-}" ]] && sed -i "s|WEB_PORT=\"9998\"|WEB_PORT=\"${WEB_PORT}\"|g" "${ws}/.env"

    # Generate per-engagement secrets (idempotent)
    secrets_init "${ws}"

    # 3. ENGAGEMENT.md
    printf '%b\n' "  ${DIM}[3/6]${RESET} ${DIM}Writing ENGAGEMENT.md...${RESET}"
    cat > "${ws}/ENGAGEMENT.md" <<DOC
# Engagement: ${target}

- **Date**: $(date '+%Y-%m-%d %H:%M')
- **Domain**: ${domain}
- **Workspace**: ${ws}
- **Proxy**: http://127.0.0.1:\${PROXY_PORT:-8080}

## Scope
TODO

## Rules of Engagement
TODO

## User-Agent
\${UA:-not set}
DOC

    # 4. Start proxy
    printf '%b\n' "  ${DIM}[4/6]${RESET} ${DIM}Starting mitmproxy...${RESET}"
    DOTSEC_WORKSPACE_ROOT="${ws_root}" TARGET="${target}" proxy_up

    # 5. Create the per-engagement Exegol container (workspace mounted, my-resources)
    printf '%b\n' "  ${DIM}[5/6]${RESET} ${DIM}Creating Exegol container...${RESET}"
    __exegol_ensure_running "$target" "$ws" || true

    # 6. Spawn tmux inside Exegol (engagement workspace is mounted at /workspace)
    printf '%b\n' "  ${DIM}[6/6]${RESET} ${DIM}Creating tmux session in Exegol...${RESET}"
    local container; container="$(__exegol_name "$target")"
    local load_cmd="source /workspace/.env; [ -f /workspace/.env.secrets ] && source /workspace/.env.secrets; export TARGET=${target} DOMAIN=${domain}; clear"
    __exegol_tmux_spawn "$container" "$target" "$load_cmd"

    echo ""
    printf '%b\n' "  ${BOLD}${GREEN}┌─ Engagement: ${CYAN}${target}${GREEN} ─────────────────┐${RESET}"
    printf '%b\n' "  ${BOLD}${GREEN}│${RESET}                                               ${BOLD}${GREEN}│${RESET}"
    printf '%b\n' "  ${BOLD}${GREEN}│${RESET}  ${BOLD}Workspace${RESET}   → ${CYAN}${ws}${RESET}"
    printf '%b\n' "  ${BOLD}${GREEN}│${RESET}  ${BOLD}Proxy${RESET}       → ${YELLOW}http://127.0.0.1:${PROXY_PORT:-9999}${RESET}"
    printf '%b\n' "  ${BOLD}${GREEN}│${RESET}  ${BOLD}Web UI${RESET}      → ${YELLOW}http://127.0.0.1:${WEB_PORT:-9998}${RESET}"
    printf '%b\n' "  ${BOLD}${GREEN}│${RESET}  ${BOLD}Exegol${RESET}      → ${BLUE}${container}${RESET} ${DIM}(tmux: ${target})${RESET}"
    printf '%b\n' "  ${BOLD}${GREEN}│${RESET}  ${BOLD}Attach${RESET}      → ${YELLOW}dotsec tmux attach${RESET}"
    printf '%b\n' "  ${BOLD}${GREEN}│${RESET}  ${BOLD}Browser${RESET}     → ${YELLOW}dotsec browser ${target}${RESET}"
    printf '%b\n' "  ${BOLD}${GREEN}│${RESET}  ${BOLD}Secrets${RESET}     → ${YELLOW}dotsec secrets ${target}${RESET}"
    printf '%b\n' "  ${BOLD}${GREEN}│${RESET}  ${BOLD}Dashboard${RESET}   → ${YELLOW}dotsec board reload${RESET}"
    printf '%b\n' "  ${BOLD}${GREEN}│${RESET}                                               ${BOLD}${GREEN}│${RESET}"
    printf '%b\n' "  ${BOLD}${GREEN}└───────────────────────────────────────────────┘${RESET}"
    echo ""

    # Start dashboard if not running
    if docker ps --filter "name=dotsec-homer" --format '{{.Names}}' 2>/dev/null | grep -q .; then
        __homer_gen_config >/dev/null 2>&1
        docker restart dotsec-homer >/dev/null 2>&1 || true
    else
        cmd_dashboard up
    fi
}

# Emit `export …` lines on stdout so a shell wrapper can `source <(dotsec env x)`.
# stdout stays clean (only the env files); errors go to stderr.
cmd_env() {
    local target="${1:-${TARGET:-}}"
    if [[ -z "$target" ]]; then
        printf '%b\n' "${RED}[!] Usage: dotsec env <target>${RESET}" >&2
        exit 1
    fi
    local envfile="${WORKSPACE_ROOT}/${target}/.env"
    local secfile="${WORKSPACE_ROOT}/${target}/.env.secrets"
    if [[ ! -f "$envfile" ]]; then
        printf '%b\n' "${RED}[!] No .env for ${target} at ${envfile}${RESET}" >&2
        exit 1
    fi
    if ! __sec_guard_envfile "$envfile"; then
        printf '%b\n' "${RED}[!] .env contains command substitution — refusing${RESET}" >&2
        exit 1
    fi
    cat "$envfile"
    if [[ -f "$secfile" ]]; then
        if ! __sec_guard_envfile "$secfile"; then
            printf '%b\n' "${RED}[!] .env.secrets contains command substitution — refusing${RESET}" >&2
            exit 1
        fi
        cat "$secfile"
    fi
}

cmd_load() {
    printf '%b\n' "${YELLOW}[!]${RESET} ${DIM}dotsec load needs the shell function.${RESET}" >&2
    printf '%b\n' "  ${DIM}Add to your zshrc:${RESET} ${YELLOW}source \"${DOTSEC_HOME}/config/shellrc.zsh\"${RESET}" >&2
    printf '%b\n' "  ${DIM}Or one-shot:${RESET} ${YELLOW}source <(dotsec env ${1:-<target>})${RESET}" >&2
    exit 1
}

cmd_unload() {
    unset TARGET DOMAIN IP UA PROGRAM PROXY_PORT WEB_PORT HTTP_PROXY HTTPS_PROXY NO_PROXY WORKSPACE
    printf '%b\n' "${DIM}Engagement vars unset${RESET}"
}

cmd_list() {
    printf '%b\n' "${BOLD}${CYAN}Engagements${RESET}"
    local found=0
    for d in "${WORKSPACE_ROOT:-/workspace}"/*/; do
        [[ -d "$d" ]] || continue
        local name domain
        name=$(basename "$d")
        local env="${d}.env"
        if [[ -f "$env" ]]; then
            domain=$(__env_domain "$env")
            [[ -z "$domain" ]] && domain="?"
            printf '%b\n' "  ${GREEN}${name}${RESET}  ${DIM}→${RESET} ${DIM}${domain}${RESET}"
        else
            printf '%b\n' "  ${DIM}${name}${RESET}  ${DIM}(no .env)${RESET}"
        fi
        found=1
    done
    [[ $found -eq 0 ]] && printf '%b\n' "  ${DIM}No engagements yet.${RESET} ${YELLOW}dotsec new <target>${RESET}"
    return 0  # don't leak the falsy [[ ]] status under set -e
}

# ── Log ───────────────────────────────────────────────────
cmd_log() {
    local target="${TARGET:-}"
    [[ -z "$target" ]] && { printf '%b\n' "${RED}[!] No engagement loaded${RESET}" >&2; exit 1; }
    local logfile="${WORKSPACE_ROOT}/${target}/logs/commands.log"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$logfile"
    "$@"
}

# ── Archive ───────────────────────────────────────────────
cmd_archive() {
    local target="${1:-${TARGET:-}}"
    local output_dir="${2:-${WORKSPACE_ROOT:-/workspace}}"

    if [[ -z "$target" ]]; then
        printf '%b\n' "${RED}[!] Usage: dotsec archive <target> [output_dir]${RESET}" >&2
        exit 1
    fi

    local ws="${WORKSPACE_ROOT:-/workspace}/${target}"
    if [[ ! -d "$ws" ]]; then
        printf '%b\n' "${RED}[!] Workspace not found: ${ws}${RESET}" >&2
        exit 1
    fi

    local container; container="$(__exegol_name "$target")"
    local timestamp
    timestamp=$(date '+%Y%m%d-%H%M%S')
    local archive_name="${target}-${timestamp}.tar.gz"
    local archive_path="${output_dir}/${archive_name}"

    printf '%b\n' "${BOLD}${CYAN}Archiving${RESET} ${GREEN}${target}${RESET} ${DIM}→${RESET} ${DIM}${archive_path}${RESET}"

    # 1. Stop proxy if running
    if docker ps --filter "name=mitmproxy-${target}" --format '{{.Names}}' 2>/dev/null | grep -q .; then
        printf '%b\n' "  ${DIM}Stopping proxy...${RESET}"
        TARGET="${target}" proxy_down
    fi

    # 2. Kill tmux session in Exegol if running
    if docker exec "$container" tmux has-session -t "$target" 2>/dev/null; then
        printf '%b\n' "  ${DIM}Killing tmux session in Exegol...${RESET}"
        docker exec "$container" tmux kill-session -t "$target" 2>/dev/null || true
    fi

    # 3. Fix permissions
    printf '%b\n' "  ${DIM}Fixing permissions...${RESET}"
    chmod -R u+rwX,go-rwx "$ws" 2>/dev/null || true

    # 4. Create archive
    printf '%b\n' "  ${DIM}Creating archive...${RESET}"
    mkdir -p "$output_dir"
    tar czf "$archive_path" -C "$(dirname "$ws")" "$(basename "$ws")" 2>/dev/null

    local size
    size=$(du -h "$archive_path" 2>/dev/null | cut -f1)

    echo ""
    printf '%b\n' "  ${GREEN}Archive ready${RESET}"
    printf '%b\n' "  ${DIM}Path${RESET}  ${CYAN}${archive_path}${RESET}"
    printf '%b\n' "  ${DIM}Size${RESET}  ${YELLOW}${size}${RESET}"
    echo ""
}

# ── Remove ───────────────────────────────────────────────
__engagement_names() {
    local d
    for d in "${WORKSPACE_ROOT:-/workspace}"/*/; do
        [[ -d "$d" ]] || continue
        basename "$d"
    done
}

cmd_rm() {
    local target="" do_archive=0 arg
    for arg in "$@"; do
        case "$arg" in
            --archive) do_archive=1 ;;
            -*) printf '%b\n' "${RED}[!] Unknown flag: ${arg}${RESET}" >&2; exit 1 ;;
            *)  [[ -z "$target" ]] && target="$arg" ;;
        esac
    done
    [[ -z "$target" ]] && target="${TARGET:-}"
    # No target given → interactive pick with fzf.
    if [[ -z "$target" ]]; then
        if command -v fzf >/dev/null 2>&1; then
            target=$(__engagement_names | fzf --prompt="rm engagement> " --height=40% --reverse \
                --preview="cat ${WORKSPACE_ROOT:-/workspace}/{}/.env 2>/dev/null" 2>/dev/null || true)
            [[ -z "$target" ]] && { printf '%b\n' "${DIM}Aborted${RESET}" >&2; exit 0; }
        else
            printf '%b\n' "${RED}[!] Usage: dotsec rm <target> [--archive]${RESET} ${DIM}(or install fzf to pick)${RESET}" >&2; exit 1
        fi
    fi
    if [[ ! "$target" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        printf '%b\n' "${RED}[!] Invalid target name: ${target}${RESET}" >&2; exit 1
    fi
    __require_docker
    local ws="${WORKSPACE_ROOT:-/workspace}/${target}"
    if [[ ! -d "$ws" ]]; then
        printf '%b\n' "${RED}[!] Engagement not found: ${target}${RESET}" >&2; exit 1
    fi
    printf '%b' "${YELLOW}[?]${RESET} Permanently remove ${CYAN}${target}${RESET} ${DIM}(${ws})${RESET}? [y/N] " >&2
    local ans; read -r ans || ans=""
    [[ "$ans" =~ ^[Yy]$ ]] || { printf '%b\n' "${DIM}Aborted${RESET}" >&2; exit 0; }

    [[ $do_archive -eq 1 ]] && cmd_archive "$target"

    # Remove the per-engagement containers (never an externally forced one)
    docker rm -f "mitmproxy-${target}" "oob-${target}" "exegol-${target}" >/dev/null 2>&1 || true

    rm -rf "$ws" 2>/dev/null || true
    if [[ -d "$ws" ]]; then
        # leftover root-owned files (proxy certs written by the root container)
        docker run --rm -v "${WORKSPACE_ROOT:-/workspace}:/ws" alpine rm -rf "/ws/${target}" >/dev/null 2>&1 || true
    fi
    if [[ -d "$ws" ]]; then
        printf '%b\n' "${YELLOW}[!]${RESET} ${DIM}some files remain (root-owned) — run:${RESET} ${YELLOW}sudo rm -rf ${ws}${RESET}" >&2
    else
        printf '%b\n' "  ${GREEN}removed${RESET} ${CYAN}${target}${RESET}"
    fi
    __homer_reload_if_running
    return 0
}

# ── Stop / Restart ───────────────────────────────────────
cmd_stop() {
    local target="${1:-${TARGET:-}}"
    if [[ -z "$target" ]]; then
        printf '%b\n' "${RED}[!] Usage: dotsec stop <target>${RESET}" >&2
        exit 1
    fi
    local container="exegol-${target}"

    printf '%b\n' "${BOLD}${YELLOW}Stopping${RESET} ${CYAN}${target}${RESET}..."

    # Stop proxy
    if docker ps --filter "name=mitmproxy-${target}" --format '{{.Names}}' 2>/dev/null | grep -q .; then
        printf '%b\n' "  ${DIM}Proxy...${RESET}"
        TARGET="${target}" proxy_down
    else
        printf '%b\n' "  ${DIM}Proxy: already stopped${RESET}"
    fi

    # Stop the Exegol container
    if docker ps --filter "name=^${container}$" --format '{{.Names}}' 2>/dev/null | grep -q .; then
        printf '%b\n' "  ${DIM}Exegol container...${RESET}"
        docker stop "$container" >/dev/null 2>&1 || true
    else
        printf '%b\n' "  ${DIM}Exegol: not running${RESET}"
    fi

    # Stop dashboard
    if docker ps --filter "name=dotsec-homer" --format '{{.Names}}' 2>/dev/null | grep -q .; then
        printf '%b\n' "  ${DIM}Dashboard...${RESET}"
        cmd_dashboard down
    else
        printf '%b\n' "  ${DIM}Dashboard: not running${RESET}"
    fi

    printf '%b\n' "  ${GREEN}Environment stopped${RESET}"
    echo ""
}

cmd_restart() {
    local target="${1:-${TARGET:-}}"
    if [[ -z "$target" ]]; then
        printf '%b\n' "${RED}[!] Usage: dotsec restart <target>${RESET}" >&2
        exit 1
    fi
    local ws="${WORKSPACE_ROOT:-/workspace}/${target}"
    local container; container="$(__exegol_name "$target")"

    if [[ ! -d "$ws" ]] || [[ ! -f "${ws}/.env" ]]; then
        printf '%b\n' "${RED}[!] Engagement not found: ${target}${RESET}" >&2
        printf '%b\n' "  Run ${YELLOW}dotsec new ${target}${RESET} first" >&2
        exit 1
    fi

    printf '%b\n' "${BOLD}${GREEN}Restarting${RESET} ${CYAN}${target}${RESET}..."

    # Reload engagement vars
    local domain
    domain=$(__env_domain "${ws}/.env")
    [[ -z "$domain" ]] && domain="${target}"

    source "${ws}/.env" 2>/dev/null || true

    # Restart proxy
    printf '%b\n' "  ${DIM}Proxy...${RESET}"
    TARGET="${target}" proxy_up

    # Ensure Exegol
    printf '%b\n' "  ${DIM}Exegol...${RESET}"
    __exegol_ensure_running "$target" "$ws" || true

    # Recreate tmux session
    printf '%b\n' "  ${DIM}Tmux session...${RESET}"
    local load_cmd="source /workspace/.env; [ -f /workspace/.env.secrets ] && source /workspace/.env.secrets; export TARGET=${target} DOMAIN=${domain}; clear"
    __exegol_tmux_spawn "$container" "$target" "$load_cmd"

    printf '%b\n' "  ${GREEN}Environment restarted${RESET}"
    printf '%b\n' "  ${DIM}Attach →${RESET} ${YELLOW}dotsec tmux attach${RESET}"

    # Restart dashboard if it was stopped
    if ! docker ps --filter "name=dotsec-homer" --format '{{.Names}}' 2>/dev/null | grep -q .; then
        cmd_dashboard up
    else
        __homer_gen_config >/dev/null 2>&1
        docker restart dotsec-homer >/dev/null 2>&1 || true
    fi
    echo ""
}

cmd_info() {
    printf '%b\n' "${BOLD}${GREEN}dotsec${RESET} ${DIM}v${VERSION}${RESET}"
    echo ""
    printf '%b\n' "  ${DIM}TARGET${RESET}      ${GREEN}${TARGET:-${DIM}not set${RESET}}${RESET}"
    printf '%b\n' "  ${DIM}DOMAIN${RESET}      ${GREEN}${DOMAIN:-${DIM}not set${RESET}}${RESET}"
    printf '%b\n' "  ${DIM}WORKSPACE${RESET}   ${CYAN}${WORKSPACE:-${DIM}not set${RESET}}${RESET}"
    printf '%b\n' "  ${DIM}HTTP_PROXY${RESET}  ${YELLOW}${HTTP_PROXY:-${DIM}not set${RESET}}${RESET}"
    printf '%b\n' "  ${DIM}UA${RESET}          ${MAGENTA}${UA:-${DIM}not set${RESET}}${RESET}"
    printf '%b\n' "  ${DIM}EXEGOL${RESET}      ${BLUE}${EXEGOL_CONTAINER:-${DIM}not set${RESET}}${RESET}"
    echo ""
    printf '%b\n' "  ${DIM}DOTSEC_HOME${RESET}    ${DIM}${DOTSEC_HOME}${RESET}"
    printf '%b\n' "  ${DIM}DOTSEC_CONFIG${RESET}  ${DIM}${DOTSEC_CONFIG}${RESET} $([ -f "${DOTSEC_CONFIG}/config" ] && printf '%b' "${GREEN}(loaded)${RESET}" || printf '%b' "${RED}(missing)${RESET}")"
}
