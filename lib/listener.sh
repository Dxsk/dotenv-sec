#!/usr/bin/env bash
# ─── lib/listener.sh ─── OOB HTTP callback container + ssh tunnel ──

cmd_listener() {
    local action="${1:-status}"; shift || true
    __require_docker
    local target="${TARGET:-default}"
    local oob_port="${OOB_PORT:-9996}"
    local ws="${WORKSPACE:-${WORKSPACE_ROOT:-/workspace}/${target}}"
    local oobdir="${ws}/oob"
    mkdir -p "$oobdir"

    case "$action" in
        up)
            local tunnel=1
            [[ "${1:-}" == "--no-tunnel" ]] && tunnel=0
            __docker_network_ensure
            printf '%b\n' "${YELLOW}[*]${RESET} ${DIM}Starting OOB listener for${RESET} ${CYAN}${target}${RESET}..."
            OOB_PORT="$oob_port" OOB_DIR="$oobdir" TARGET="$target" \
                docker compose -f "${DOTSEC_HOME}/listener/docker-compose.yml" \
                --project-name dotsec-oob up -d --build >/dev/null 2>&1 || true
            printf '%b\n' "  ${GREEN}Local${RESET}  ${YELLOW}http://127.0.0.1:${oob_port}${RESET}"
            printf '%b\n' "  ${GREEN}Logs${RESET}   ${DIM}${oobdir}/hits.log${RESET}"
            if [[ $tunnel -eq 1 ]]; then
                : > "${oobdir}/tunnel.log"
                ssh -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=60 \
                    -R "80:localhost:${oob_port}" nokey@localhost.run \
                    > "${oobdir}/tunnel.log" 2>&1 &
                echo $! > "${oobdir}/tunnel.pid"
                local url="" i=0
                while [[ -z "$url" && $i -lt "${OOB_TUNNEL_WAIT:-20}" ]]; do
                    url=$(grep -oE 'https://[a-z0-9.-]+\.(lhr\.life|serveo\.net)' "${oobdir}/tunnel.log" 2>/dev/null | head -1 || true)
                    [[ -n "$url" ]] && break
                    sleep 1; i=$((i+1))
                done
                if [[ -n "$url" ]]; then
                    printf '%s\n' "$url" > "${oobdir}/url.txt"
                    printf '%b\n' "  ${GREEN}Public${RESET} ${YELLOW}${url}${RESET}"
                else
                    printf '%b\n' "  ${YELLOW}[!]${RESET} ${DIM}tunnel URL not captured yet — check ${oobdir}/tunnel.log${RESET}" >&2
                fi
            fi
            return 0
            ;;
        down)
            docker compose -f "${DOTSEC_HOME}/listener/docker-compose.yml" \
                --project-name dotsec-oob down >/dev/null 2>&1 || true
            if [[ -f "${oobdir}/tunnel.pid" ]]; then
                kill "$(cat "${oobdir}/tunnel.pid")" 2>/dev/null || true
                rm -f "${oobdir}/tunnel.pid" "${oobdir}/url.txt"
            fi
            printf '%b\n' "${DIM}OOB listener stopped${RESET}"
            return 0
            ;;
        logs)
            tail -f "${oobdir}/hits.log" 2>/dev/null || { printf '%b\n' "${DIM}no hits yet${RESET}"; return 0; }
            ;;
        status)
            docker ps --filter "name=oob-${target}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
            [[ -f "${oobdir}/url.txt" ]] && printf '%b\n' "  ${GREEN}URL${RESET} ${YELLOW}$(cat "${oobdir}/url.txt")${RESET}"
            return 0
            ;;
        *)
            printf '%b\n' "${RED}[!] Usage: dotsec listener up [--no-tunnel]|down|logs|status${RESET}" >&2
            return 1
            ;;
    esac
}
