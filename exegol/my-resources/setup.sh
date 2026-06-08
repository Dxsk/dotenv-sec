#!/usr/bin/env bash
# ─── dotenv-sec :: Exegol My Resources Setup ──────────────
# Installs uv (Python package manager) and pnpm (Node.js package manager)
# globally inside Exegol containers.
#
# Usage (from inside Exegol container as root):
#   bash /opt/resources/dotenv-sec/setup.sh
#
# Usage (from host):
#   docker exec -it <container> bash /opt/resources/dotenv-sec/setup.sh
#   dotsec exegol setup
set -euo pipefail

GREEN="\033[32m"
CYAN="\033[36m"
YELLOW="\033[33m"
BOLD="\033[1m"
RESET="\033[0m"

echo -e "${BOLD}${CYAN}╔══════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║  dotenv-sec :: Exegol Tool Setup     ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${RESET}"
echo ""

# ── uv ────────────────────────────────────────────────────
install_uv() {
    if command -v uv &>/dev/null; then
        echo -e "  ${GREEN}[✓] uv already installed${RESET} ($(uv --version 2>/dev/null))"
        return 0
    fi

    echo -e "  ${CYAN}[*] Installing uv...${RESET}"
    curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="/usr/local/bin" sh

    if command -v uv &>/dev/null; then
        echo -e "  ${GREEN}[+] uv installed${RESET} ($(uv --version 2>/dev/null))"
    else
        echo -e "  ${YELLOW}[!] uv install may have failed${RESET}"
    fi
}

# ── pnpm ──────────────────────────────────────────────────
install_pnpm() {
    if command -v pnpm &>/dev/null; then
        echo -e "  ${GREEN}[✓] pnpm already installed${RESET} ($(pnpm --version 2>/dev/null))"
        return 0
    fi

    echo -e "  ${CYAN}[*] Installing pnpm...${RESET}"

    # Prefer npm global install (npm is present in Exegol images)
    if command -v npm &>/dev/null; then
        npm install -g pnpm 2>/dev/null && {
            echo -e "  ${GREEN}[+] pnpm installed via npm${RESET} ($(pnpm --version 2>/dev/null))"
            return 0
        }
    fi

    # Fallback: corepack
    if command -v corepack &>/dev/null; then
        corepack enable && corepack prepare pnpm@latest --activate 2>/dev/null && {
            echo -e "  ${GREEN}[+] pnpm installed via corepack${RESET} ($(pnpm --version 2>/dev/null))"
            return 0
        }
    fi

    # Last resort: standalone install script
    curl -fsSL https://get.pnpm.io/install.sh | env PNPM_HOME="/usr/local/bin" sh - 2>/dev/null && {
        if command -v pnpm &>/dev/null; then
            echo -e "  ${GREEN}[+] pnpm installed via standalone${RESET} ($(pnpm --version 2>/dev/null))"
            return 0
        fi
    }

    echo -e "  ${YELLOW}[!] pnpm install failed (no npm/corepack/curl available)${RESET}"
}

# ── Main ──────────────────────────────────────────────────
install_uv
install_pnpm

echo ""
echo -e "${BOLD}${GREEN}[✓] Setup complete${RESET}"
echo ""
echo -e "  uv    → $(command -v uv 2>/dev/null || echo 'NOT FOUND')"
echo -e "  uvx   → $(command -v uvx 2>/dev/null || echo 'NOT FOUND')"
echo -e "  pnpm  → $(command -v pnpm 2>/dev/null || echo 'NOT FOUND')"
