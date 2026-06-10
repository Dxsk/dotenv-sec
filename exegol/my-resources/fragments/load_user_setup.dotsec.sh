# shellcheck shell=bash
# dotsec recon tooling — runs on first container start. Idempotent.
if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh
fi
if ! command -v pnpm >/dev/null 2>&1; then
    npm install -g pnpm 2>/dev/null || true
fi
if ! command -v unwebpack-sourcemap >/dev/null 2>&1; then
    npm install -g unwebpack-sourcemap 2>/dev/null || true
fi
# url/endpoint harvesting helpers (ProjectDiscovery + LinkFinder are already in Exegol)
if ! command -v waybackurls >/dev/null 2>&1; then
    go install github.com/tomnomnom/waybackurls@latest 2>/dev/null || true
fi
