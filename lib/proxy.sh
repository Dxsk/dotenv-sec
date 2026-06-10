#!/usr/bin/env bash
# ─── lib/proxy.sh ─── mitmproxy and browser commands ──

# ── Proxy commands ──────────────────────────────────────
proxy_up() {
    local target="${TARGET:-default}"
    local proxy_port="${PROXY_PORT:-9999}"
    local web_port="${WEB_PORT:-9998}"
    local ws_root="${DOTSEC_WORKSPACE_ROOT:-${WORKSPACE_ROOT}}"

    __require_docker
    __docker_network_ensure

    printf '%b\n' "${YELLOW}[*]${RESET} ${DIM}Starting mitmproxy for${RESET} ${CYAN}${target}${RESET}..."

    local ws="${WORKSPACE:-${ws_root}/${target}}"
    mkdir -p "${ws}/proxy/certs" "${ws}/proxy/flows"

    # Check port availability
    set +e
    ss -tlnp 2>/dev/null | grep -q ":${proxy_port}\b"
    local ss_rc=$?
    docker ps --format '{{.Ports}}' 2>/dev/null | grep -q ":${proxy_port}->"
    local docker_rc=$?
    set -e
    if [[ $ss_rc -eq 0 ]] || [[ $docker_rc -eq 0 ]]; then
        printf '%b\n' "  ${YELLOW}[!]${RESET} ${DIM}Port ${proxy_port} already in use — is another proxy running?${RESET}" >&2
        printf '%b\n' "  ${DIM}Check:${RESET} ${YELLOW}dotsec proxy status${RESET}" >&2
        printf '%b\n' "  ${DIM}Stop previous:${RESET} ${YELLOW}dotsec stop <target>${RESET}" >&2
        printf '%b\n' "  ${DIM}Or use custom port:${RESET} ${YELLOW}PROXY_PORT=8888 dotsec new ${target}${RESET}" >&2
        return 1
    fi

    # Web password: source of truth is .env.secrets (MITMWEB_PASS).
    local web_pass="${MITMWEB_PASS:-}"
    local secfile="${ws}/.env.secrets"
    if [[ -z "$web_pass" ]] && [[ -f "$secfile" ]]; then
        web_pass=$(grep -oP '^(export\s+)?MITMWEB_PASS="?\K[^"]+' "$secfile" 2>/dev/null | head -1)
    fi
    # Legacy fallback: pre-secrets engagements used certs/.web-pass
    local passfile="${ws}/proxy/certs/.web-pass"
    if [[ -z "$web_pass" ]]; then
        if [[ -f "$passfile" ]]; then
            web_pass=$(cat "$passfile" 2>/dev/null || echo "")
        fi
        if [[ -z "$web_pass" ]]; then
            web_pass=$(set +o pipefail; LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)
            echo "$web_pass" > "$passfile"
        fi
    fi

    # Build image only if missing
    local build_flag=""
    if ! docker image inspect dotenv-sec/mitmproxy:latest &>/dev/null; then
        build_flag="--build"
    fi

    set +e
    TARGET="${target}" \
        PROXY_PORT="${proxy_port}" \
        WEB_PORT="${web_port}" \
        WEB_USER="admin" \
        WEB_PASS="${web_pass}" \
        PROXY_CERTS="${ws}/proxy/certs" \
        PROXY_FLOWS="${ws}/proxy/flows" \
        docker compose -f "${DOTSEC_HOME}/mitmproxy/docker-compose.yml" \
        --project-name "dotsec-${target}" up -d ${build_flag} >/dev/null 2>&1
    local compose_rc=$?
    set -e

    if [[ $compose_rc -ne 0 ]]; then
        printf '%b\n' "  ${RED}[!]${RESET} ${DIM}Failed to start proxy — port ${proxy_port} may be in use${RESET}" >&2
        printf '%b\n' "  ${DIM}Check:${RESET} ${YELLOW}dotsec proxy status${RESET} ${DIM}or${RESET} ${YELLOW}dotsec stop <target>${RESET}" >&2
        return 1
    fi

    printf '%b\n' "  ${GREEN}Proxy${RESET}   ${YELLOW}http://127.0.0.1:${proxy_port}${RESET}"
    printf '%b\n' "  ${GREEN}Web UI${RESET}  ${YELLOW}http://127.0.0.1:${web_port}${RESET}"
    printf '%b\n' "  ${GREEN}Web auth${RESET} ${DIM}admin :${RESET} ${YELLOW}${web_pass}${RESET}"
    printf '%b\n' "  ${GREEN}CA PEM${RESET}  ${DIM}${ws}/proxy/certs/mitmproxy-ca-cert.pem${RESET}"

    __homer_reload_if_running
}

proxy_down() {
    local target="${TARGET:-default}"
    docker compose -f "${DOTSEC_HOME}/mitmproxy/docker-compose.yml" \
        --project-name "dotsec-${target}" down
    printf '%b\n' "${DIM}Proxy stopped for${RESET} ${CYAN}${target}${RESET}"
}

proxy_status() {
    local target="${TARGET:-default}"
    docker ps --filter "name=mitmproxy-${target}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

proxy_logs() {
    local target="${TARGET:-default}"
    docker logs -f "mitmproxy-${target}"
}

# ── Browser ──────────────────────────────────────────────
cmd_browser() {
    local target="${1:-${TARGET:-}}"
    __require_docker
    if [[ -z "$target" ]]; then
        printf '%b\n' "${RED}[!] Usage: dotsec browser <target>  (or dotsec load first)${RESET}" >&2
        exit 1
    fi
    local ws="${WORKSPACE_ROOT}/${target}"

    # Ensure proxy is up
    if ! docker ps --filter "name=mitmproxy-${target}" --format '{{.Names}}' | grep -q .; then
        printf '%b\n' "${YELLOW}[!]${RESET} ${DIM}Proxy not running. Starting...${RESET}" >&2
        TARGET="${target}" proxy_up
    fi

    local proxy_host="mitmproxy-${target}"

    # Display forwarding. Prefer NATIVE WAYLAND: under GNOME/Mutter (and most
    # Wayland compositors) Chromium's X11 software bitmap presenter cannot paint
    # into an XWayland window ("XGetWindowAttributes failed"), so the window
    # never shows. Speaking Wayland to the host compositor bypasses XWayland
    # entirely. Fall back to X11 for non-Wayland (native Xorg) sessions.
    local display=() flags="--no-sandbox --disable-dev-shm-usage --disable-features=TranslateUI"
    local wl_sock="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/${WAYLAND_DISPLAY:-wayland-0}"
    if [[ -n "${WAYLAND_DISPLAY:-}" ]] && [[ -S "$wl_sock" ]]; then
        display=(--ipc=host
            -e XDG_RUNTIME_DIR=/tmp
            -e "WAYLAND_DISPLAY=${WAYLAND_DISPLAY}"
            -v "${wl_sock}:/tmp/${WAYLAND_DISPLAY}")
        flags+=" --ozone-platform=wayland --enable-features=UseOzonePlatform"
    elif [[ -n "${DISPLAY:-}" ]]; then
        display=(--ipc=host
            -e "DISPLAY=${DISPLAY}"
            -v /tmp/.X11-unix:/tmp/.X11-unix:ro)
        local xauth="${XAUTHORITY:-$HOME/.Xauthority}"
        [[ -f "$xauth" ]] && display+=(-e XAUTHORITY=/tmp/.Xauthority -v "${xauth}:/tmp/.Xauthority:ro")
        flags+=" --disable-gpu --ozone-platform=x11"
    fi

    # Extensions (runtime, managed by `dotsec ext sync`) + favourites policy.
    local extra=()
    local ext_dir="${DOTSEC_EXT_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/dotenvsec/extensions}"
    if [[ -d "$ext_dir" ]] && [[ -n "$(ls -A "$ext_dir" 2>/dev/null)" ]]; then
        extra+=(-v "${ext_dir}:/extensions:ro")
    fi
    local bm="${DOTSEC_HOME}/chromium/managed-bookmarks.json"
    local user_bm="${XDG_CONFIG_HOME:-$HOME/.config}/dotenvsec/bookmarks.json"
    if [[ -f "$user_bm" ]]; then bm="$user_bm"; fi
    if [[ -f "$bm" ]]; then
        extra+=(-v "${bm}:/etc/chromium/policies/managed/dotsec.json:ro")
    fi

    docker run --rm \
        --network dotsec-proxy-net \
        -e HTTP_PROXY="http://${proxy_host}:8080" \
        -e HTTPS_PROXY="http://${proxy_host}:8080" \
        -e CHROMIUM_FLAGS="${flags}" \
        "${display[@]}" \
        "${extra[@]}" \
        -v "${ws}/proxy/certs:/certs:ro" \
        -p 127.0.0.1:9222:9222 \
        dotenv-sec/chromium:latest
}
