#!/usr/bin/env bash
# ─── lib/dashboard.sh ─── Homer dashboard helpers ──

__homer_reload_if_running() {
    if docker ps --filter "name=dotsec-homer" --format '{{.Names}}' 2>/dev/null | grep -q .; then
        __homer_gen_config >/dev/null 2>&1
        docker restart dotsec-homer >/dev/null 2>&1 || true
    fi
}

# ── Dashboard (Homer) ────────────────────────────────────
__homer_gen_config() {
    local config="${DOTSEC_HOME}/homer/config.yml"
    local base="${DOTSEC_HOME}/homer/config.base.yml"

    # Use base template if available, else inline
    if [[ -f "$base" ]]; then
        cp "$base" "$config"
    else
        cat > "$config" <<'YAML'
---
title: "dotenv-sec"
subtitle: "Pentest Dashboard"
header: true
footer: false
columns: "auto"
connectivityCheck: true
theme: dark
colors:
  light:
    highlight-primary: "#0d7377"
    highlight-secondary: "#14a3a8"
    highlight-hover: "#0fa0a5"
    background: "#f5f5f5"
    card-background: "#ffffff"
    text: "#363636"
    text-header: "#212529"
    text-title: "#212529"
    text-subtitle: "#424242"
    card-shadow: "rgba(0,0,0,0.1)"
    link: "#14a3a8"
    link-hover: "#0d7377"
  dark:
    highlight-primary: "#14a3a8"
    highlight-secondary: "#0d7377"
    highlight-hover: "#18b5ba"
    background: "#0d1117"
    card-background: "#161b22"
    text: "#e6edf3"
    text-header: "#e6edf3"
    text-title: "#ffffff"
    text-subtitle: "#b0b8c4"
    card-shadow: "rgba(20,163,168,0.10)"
    link: "#14a3a8"
    link-hover: "#18b5ba"
YAML
    fi

    # Inject services
    cat >> "$config" <<YAML

services:
YAML

    # Detection d'engagements actifs
    local found=0
    for d in "${WORKSPACE_ROOT:-/workspace}"/*/; do
        [[ -d "$d" ]] || continue
        local target domain
        target=$(basename "$d")
        local envfile="${d}.env"
        domain=""

        [[ -f "$envfile" ]] && domain=$(__env_domain "$envfile")
        [[ -z "$domain" ]] && domain="${target}"

        # Check if proxy is running
        local proxy_status="down"
        docker ps --filter "name=mitmproxy-${target}" --format '{{.Names}}' 2>/dev/null | grep -q . && proxy_status="up"

        cat >> "$config" <<BLOCK
  - name: "${target}"
    icon: "fas fa-crosshairs"
    subtitle: "${domain}"
    items:
      - name: "Proxy: ${proxy_status}"
        icon: "fas fa-network-wired"
        subtitle: "127.0.0.1:9999"
        url: "http://127.0.0.1:9999"
        target: "_blank"
      - name: "mitmweb UI"
        icon: "fas fa-globe"
        subtitle: "127.0.0.1:9998"
        url: "http://127.0.0.1:9998"
        target: "_blank"
      - name: "Workspace"
        icon: "fas fa-folder"
        subtitle: "${target}"
        url: "file://${WORKSPACE_ROOT}/${target}"
      - name: "ENGAGEMENT.md"
        icon: "fas fa-file-alt"
        subtitle: "scope, rules"
        url: "file://${WORKSPACE_ROOT}/${target}/ENGAGEMENT.md"
BLOCK
        found=1
    done

    # Fallback if no engagements
    if [[ $found -eq 0 ]]; then
        cat >> "$config" <<YAML
  - name: "No engagements"
    icon: "fas fa-circle-notch"
    items:
      - name: "Create one"
        icon: "fas fa-plus"
        subtitle: "dotsec new <target>"
        url: "#"
YAML
    fi

    echo "  → ${config}"
}

cmd_dashboard() {
    local action="${1:-status}"

    __require_docker

    case "$action" in
        up|start)
            printf '%b\n' "${DIM}Generating Homer config...${RESET}"
            __homer_gen_config

            printf '%b\n' "${DIM}Starting Homer dashboard...${RESET}"
            __docker_network_ensure

            docker compose -f "${DOTSEC_HOME}/homer/docker-compose.yml" \
                --project-name "dotsec-homer" up -d

            printf '%b\n' "  ${GREEN}Dashboard${RESET} ${YELLOW}http://127.0.0.1:${HOMER_PORT:-9997}${RESET}"
            ;;
        down|stop)
            docker compose -f "${DOTSEC_HOME}/homer/docker-compose.yml" \
                --project-name "dotsec-homer" down
            printf '%b\n' "${DIM}Dashboard stopped${RESET}"
            ;;
        reload)
            printf '%b\n' "${DIM}Regenerating config + restarting...${RESET}"
            __homer_gen_config
            docker restart dotsec-homer 2>/dev/null || \
                { printf '%b\n' "${YELLOW}[!]${RESET} ${DIM}Homer not running, starting...${RESET}" >&2; cmd_dashboard up; }
            printf '%b\n' "${DIM}Dashboard reloaded${RESET}"
            ;;
        status)
            docker ps --filter "name=dotsec-homer" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
            ;;
        *)
            printf '%b\n' "${RED}[!] Usage: dotsec dashboard up|down|reload|status${RESET}" >&2
            ;;
    esac
}
