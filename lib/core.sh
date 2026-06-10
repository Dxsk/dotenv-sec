#!/usr/bin/env bash
# ─── lib/core.sh ─── shared Docker/env helpers ──

__docker_network_ensure() {
    local net="${1:-dotsec-proxy-net}"
    docker network inspect "$net" &>/dev/null || docker network create "$net"
}

__env_domain() {
    local domain
    domain=$(grep -oP 'DOMAIN="?\K[^"]+' "$1" 2>/dev/null || echo "")
    echo "${domain}"
}

# ── Global config (always sourced, overridden per-engagement) ──
__dotsec_load_global() {
    if [[ -f "${DOTSEC_CONFIG}/config" ]]; then
        source "${DOTSEC_CONFIG}/config"
    fi
    # Auto-detect Exegol container if not set
    if [[ -z "${EXEGOL_CONTAINER:-}" ]]; then
        local detected
        detected=$(docker ps -a --filter "name=exegol" --format '{{.Names}}' 2>/dev/null | head -1)
        [[ -n "$detected" ]] && EXEGOL_CONTAINER="$detected"
    fi
}

__require_docker() {
    if [[ -z "$(command -v docker)" ]]; then
        printf '%b\n' "${RED}[!] docker is required but not installed${RESET}" >&2
        exit 1
    fi
}
