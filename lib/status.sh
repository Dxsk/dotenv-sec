#!/usr/bin/env bash
# ─── lib/status.sh ─── engagement status overview ──

__status_global() {
    local exegol="${EXEGOL_CONTAINER:-exegol}"
    local ex_state="stopped" db_state="down"
    docker ps --filter "name=^${exegol}$" --format '{{.Names}}' 2>/dev/null | grep -q . && ex_state="running"
    docker ps --filter "name=dotsec-homer" --format '{{.Names}}' 2>/dev/null | grep -q . \
        && db_state="up (127.0.0.1:${HOMER_PORT:-9997})"
    printf '%b\n' "${BOLD}${CYAN}Global${RESET}   ${DIM}Exegol:${RESET} ${ex_state}   ${DIM}Dashboard:${RESET} ${db_state}"
    return 0
}

__status_engagement() {
    local target="$1" ws="$2"
    local domain proxy tmuxs size loot last pport wport exegol
    domain=$(__env_domain "${ws}/.env"); [[ -z "$domain" ]] && domain="?"
    pport=$(grep -oP 'PROXY_PORT="?\K[0-9]+' "${ws}/.env" 2>/dev/null | head -1 || true); pport="${pport:-9999}"
    wport=$(grep -oP 'WEB_PORT="?\K[0-9]+' "${ws}/.env" 2>/dev/null | head -1 || true); wport="${wport:-9998}"
    proxy="down"
    if docker ps --filter "name=mitmproxy-${target}" --format '{{.Names}}' 2>/dev/null | grep -q .; then
        proxy="up    127.0.0.1:${pport} / ${wport}"
    fi
    tmuxs="—"
    exegol="${EXEGOL_CONTAINER:-exegol}"
    if docker ps --filter "name=^${exegol}$" --format '{{.Names}}' 2>/dev/null | grep -q .; then
        docker exec "$exegol" tmux has-session -t "$target" 2>/dev/null && tmuxs="session present"
    fi
    size=$(du -sh "$ws" 2>/dev/null | cut -f1 || true); size="${size:-?}"
    loot=$(find "${ws}/recon/loot" -type f 2>/dev/null | wc -l || true); loot="${loot:-0}"
    last=$(find "$ws" -type f -printf '%TY-%Tm-%Td %TH:%TM\n' 2>/dev/null | sort -r | head -1 || true); last="${last:-?}"
    printf '%b\n' "${GREEN}${target}${RESET}  ${DIM}→ ${domain}${RESET}"
    printf '%b\n' "  ${DIM}Proxy${RESET}      ${proxy}"
    printf '%b\n' "  ${DIM}Tmux${RESET}       ${tmuxs}"
    printf '%b\n' "  ${DIM}Workspace${RESET}  ${size}   ${DIM}loot:${RESET} ${loot}   ${DIM}last:${RESET} ${last}"
    return 0
}

cmd_status() {
    local only="${1:-}"
    __require_docker
    __status_global
    echo ""
    local found=0 d target
    for d in "${WORKSPACE_ROOT:-/workspace}"/*/; do
        [[ -d "$d" ]] || continue
        target=$(basename "$d")
        [[ -n "$only" && "$target" != "$only" ]] && continue
        __status_engagement "$target" "${d%/}"
        found=1
    done
    [[ $found -eq 0 ]] && printf '%b\n' "  ${DIM}No engagements yet.${RESET} ${YELLOW}dotsec new <target>${RESET}"
    return 0
}
