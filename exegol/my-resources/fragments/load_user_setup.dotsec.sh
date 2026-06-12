# shellcheck shell=bash
# dotsec offensive tooling installer — runs on first container start and on
# `dotsec exegol setup`. Idempotent and best-effort: a single failed install
# never aborts the container build. Tools already shipped by the Exegol image
# (subfinder/httpx/katana/naabu/nuclei/gowitness/ffuf/gau/semgrep/trufflehog/
# gitleaks) are NOT reinstalled — only what the dotsec scripts need on top.
#
# go install writes to an asdf-managed GOPATH that is NOT on PATH, so binaries
# are forced into /usr/local/bin (on PATH, writable). go tools are best-effort:
# many now require go >= 1.23 while the base image may ship 1.22 — if the build
# fails the script falls back (scan-takeover→nuclei, sourcemaps→unwebpack, …).
_dotsec_gobin="/usr/local/bin"

_dotsec_have() { command -v "$1" >/dev/null 2>&1; }

_dotsec_pipx() {  # _dotsec_pipx <bin> <pypi-spec>
    _dotsec_have "$1" && return 0
    pipx install "$2" >/dev/null 2>&1 || true
}

_dotsec_go() {    # _dotsec_go <bin> <module@version>   (best-effort)
    _dotsec_have "$1" && return 0
    GOBIN="$_dotsec_gobin" go install "$2" >/dev/null 2>&1 || true
}

_dotsec_release() {  # _dotsec_release <bin> <url-amd64> <url-arm64>
    _dotsec_have "$1" && return 0
    local url
    case "$(uname -m)" in
        x86_64 | amd64) url="$2" ;;
        aarch64 | arm64) url="$3" ;;
        *) return 0 ;;
    esac
    if curl -fsSL "$url" -o "${_dotsec_gobin}/$1" 2>/dev/null; then
        chmod +x "${_dotsec_gobin}/$1" 2>/dev/null || true
    fi
}

echo "[dotsec] provisioning recon/scan/audit tooling (idempotent)…"

# ── base runtimes ───────────────────────────────────────
_dotsec_have uv || curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh
_dotsec_have pnpm || npm install -g pnpm >/dev/null 2>&1 || true

# ── recon: JS endpoint extraction + sourcemap reconstruction ──
_dotsec_pipx xnLinkFinder xnLinkFinder
_dotsec_have unwebpack-sourcemap || npm install -g unwebpack-sourcemap >/dev/null 2>&1 || true
_dotsec_go sourcemapper github.com/denandz/sourcemapper@latest

# ── recon: passive URL aggregation (recon-urls) ─────────
_dotsec_go waybackurls github.com/tomnomnom/waybackurls@latest
_dotsec_pipx waymore waymore
_dotsec_go urlfinder github.com/projectdiscovery/urlfinder/cmd/urlfinder@latest

# ── scan: subdomain takeover (bonus — scan-takeover falls back to nuclei) ──
_dotsec_go subzy github.com/PentestPad/subzy@latest

# ── code audit: SCA (audit-code; semgrep/trufflehog/gitleaks ship with Exegol) ──
_dotsec_release osv-scanner \
    https://github.com/google/osv-scanner/releases/latest/download/osv-scanner_linux_amd64 \
    https://github.com/google/osv-scanner/releases/latest/download/osv-scanner_linux_arm64

# ── code audit: structural search engines (audit-sinks/audit-endpoints) ──
# ast-grep installs the `ast-grep` binary (it also ships `sg`, but /usr/bin/sg is
# the unrelated setgid tool — scripts always call `ast-grep`).
_dotsec_have ast-grep || npm install -g @ast-grep/cli >/dev/null 2>&1 || true
# weggli: C/C++ semantic grep (slow cargo build, best-effort).
_dotsec_have weggli || cargo install weggli --locked >/dev/null 2>&1 || true

echo "[dotsec] tooling ready (go-built extras skipped if go < 1.23 — covered by fallbacks)."
