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
    # Exegol containers are per-engagement (exegol-<target>, see __exegol_name).
    # EXEGOL_CONTAINER stays unset unless the user forces one in their config —
    # no auto-detection, which would otherwise pin every engagement to whichever
    # exegol-* container happens to be running.
    return 0
}

__require_docker() {
    if [[ -z "$(command -v docker)" ]]; then
        printf '%b\n' "${RED}[!] docker is required but not installed${RESET}" >&2
        exit 1
    fi
}
