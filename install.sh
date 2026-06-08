#!/usr/bin/env bash
# ─── dotsec install ─────────────────────────────────────
# One-shot setup: symlink dotsec to ~/.local/bin, add shell integration
set -euo pipefail

DOTSEC_HOME="${DOTSEC_HOME:-$(dirname "$(readlink -f "$0")")}"
BIN_DIR="${HOME}/.local/bin"

mkdir -p "${BIN_DIR}"

# Symlink binaries
for bin in dotsec dotsec-completions; do
    rm -f "${BIN_DIR}/${bin}"
    ln -s "${DOTSEC_HOME}/bin/${bin}" "${BIN_DIR}/${bin}"
    echo "[+] Linked ${bin} → ${BIN_DIR}/${bin}"
done

# Shell integration
SHELLRC="${HOME}/.zshrc"

# ── Global config dir ───────────────────────────────────
DOTSEC_CONFIG_DIR="${HOME}/.config/dotenvsec"
mkdir -p "${DOTSEC_CONFIG_DIR}/templates"
if [[ ! -f "${DOTSEC_CONFIG_DIR}/config" ]]; then
    cp "${DOTSEC_HOME}/config/global-defaults" "${DOTSEC_CONFIG_DIR}/config"
    echo "[+] Global config created at ${DOTSEC_CONFIG_DIR}/config"
else
    echo "[i] Global config already exists at ${DOTSEC_CONFIG_DIR}/config"
fi
SHELLRC_LINE="export PATH=\"\${HOME}/.local/bin:\${PATH}\""

if ! grep -qF "${SHELLRC_LINE}" "${SHELLRC}" 2>/dev/null; then
    echo "" >> "${SHELLRC}"
    echo "# dotenv-sec" >> "${SHELLRC}"
    echo "${SHELLRC_LINE}" >> "${SHELLRC}"
    echo 'export DOTSEC_HOME="$HOME/Documents/github.com/Dxsk/dotenv-sec"' >> "${SHELLRC}"
    echo 'source <(dotsec completions zsh 2>/dev/null)' >> "${SHELLRC}"
    echo "[+] Shell integration added to ${SHELLRC}"
else
    echo "[i] Shell integration already in ${SHELLRC}"
fi

# Build docker images
echo ""
echo "[*] Building docker images..."
docker build -t dotenv-sec/mitmproxy:latest "${DOTSEC_HOME}/mitmproxy" && echo "[+] mitmproxy image built"
docker build -t dotenv-sec/chromium:latest "${DOTSEC_HOME}/chromium" && echo "[+] chromium image built"

echo ""
echo -e "\033[1;32m[✓] dotsec installed!\033[0m"
echo "  Restart your shell or run: source ~/.zshrc"
echo "  Try: dotsec help"
