#!/usr/bin/env bash
# tests/integration-smoke.sh — Docker-backed integration smoke for dotsec.
#
# NOT run by CI (`bats tests/` only picks up *.bats). Run manually on a host
# with Docker and the images built:
#   make build          # once, to build dotenv-sec/mitmproxy + chromium
#   make smoke          # or: bash tests/integration-smoke.sh
#
# It uses a throwaway workspace and high ports (1999x) so it will NOT touch your
# real engagements, and a `trap` cleans up every container/dir on exit.
#
# Scope: proxy lifecycle, MITMWEB_PASS wiring, dashboard, secrets/rotate via the
# real CLI. The full `dotsec new` (Exegol pull + tmux, ~2 min, interactive) is
# left for manual verification.
#
# ok()/ko() below always return 0, so the `cond && ok || ko` pattern is safe
# (ko never runs when cond is true). Silence SC2015 for the whole file.
# shellcheck disable=SC2015
set -uo pipefail

DOTSEC_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; export DOTSEC_HOME
DOTSEC="${DOTSEC_HOME}/bin/dotsec"

WS="$(mktemp -d)"; CFG="$(mktemp -d)"
export WORKSPACE_ROOT="$WS" DOTSEC_CONFIG="$CFG"
export PROXY_PORT=19999 WEB_PORT=19998 HOMER_PORT=19997
TARGET="smoke-$$"

pass=0; fail=0
ok(){ printf '  \033[32m✓\033[0m %s\n' "$1"; pass=$((pass+1)); }
ko(){ printf '  \033[31m✗\033[0m %s\n' "$1"; fail=$((fail+1)); }
have(){ command -v "$1" >/dev/null 2>&1; }

cleanup() {
    echo "[*] cleanup"
    TARGET="$TARGET" "$DOTSEC" proxy down >/dev/null 2>&1 || true
    docker rm -f "mitmproxy-${TARGET}" >/dev/null 2>&1 || true
    "$DOTSEC" board down >/dev/null 2>&1 || true
    rm -rf "$WS" "$CFG"
}
trap cleanup EXIT

echo "=== dotsec integration smoke (target=${TARGET}, proxy:${PROXY_PORT}/web:${WEB_PORT}) ==="
have docker || { echo "[!] docker not found"; exit 1; }
docker image inspect dotenv-sec/mitmproxy:latest >/dev/null 2>&1 \
    || { echo "[!] image dotenv-sec/mitmproxy:latest missing — run: make build"; exit 1; }

# [1] secrets generation (as `dotsec new` would, without Exegol/tmux)
echo "[1] secrets generation"
# shellcheck source=/dev/null
source "${DOTSEC_HOME}/lib/ui.sh"
# shellcheck source=/dev/null
source "${DOTSEC_HOME}/lib/core.sh"
# shellcheck source=/dev/null
source "${DOTSEC_HOME}/lib/secrets.sh"
secrets_init "${WS}/${TARGET}"
printf 'export TARGET="%s"\nexport DOMAIN="example.com"\n' "$TARGET" > "${WS}/${TARGET}/.env"
[ -f "${WS}/${TARGET}/.env.secrets" ] && ok ".env.secrets created" || ko ".env.secrets missing"
[ "$(stat -c '%a' "${WS}/${TARGET}/.env.secrets" 2>/dev/null)" = "600" ] && ok ".env.secrets is 600" || ko ".env.secrets perms wrong"
[ -f "${WS}/${TARGET}/keys/id_ed25519" ] && ok "ssh key created" || ko "ssh key missing"

# [2] proxy up — must read MITMWEB_PASS from .env.secrets
echo "[2] proxy up"
want_pass="$(grep -oE 'MITMWEB_PASS="[^"]+"' "${WS}/${TARGET}/.env.secrets" | cut -d'"' -f2)"
out="$(TARGET="$TARGET" "$DOTSEC" proxy up 2>&1)"
echo "$out" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^/    /'
docker ps --format '{{.Names}}' | grep -q "mitmproxy-${TARGET}" && ok "container running" || ko "container not running"
echo "$out" | grep -q "$want_pass" && ok "web pass matches .env.secrets" || ko "web pass mismatch"

# [3] proxy status + web UI
echo "[3] proxy status + web UI"
TARGET="$TARGET" "$DOTSEC" proxy status | grep -q "mitmproxy-${TARGET}" && ok "status shows container" || ko "status missing"
if have curl; then
    sleep 2
    code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${WEB_PORT}" 2>/dev/null || echo 000)"
    { [ "$code" = "401" ] || [ "$code" = "200" ]; } && ok "web UI responds (${code})" || ko "web UI no/unexpected response (${code})"
else
    echo "  (curl absent — skip HTTP check)"
fi

# [4] proxy down
echo "[4] proxy down"
TARGET="$TARGET" "$DOTSEC" proxy down >/dev/null 2>&1
docker ps --format '{{.Names}}' | grep -q "mitmproxy-${TARGET}" && ko "container still up" || ok "container stopped"

# [5] secrets + rotate via CLI
echo "[5] secrets + rotate via CLI"
"$DOTSEC" secrets "$TARGET" | grep -q DOTSEC_API_TOKEN && ok "secrets status shown" || ko "secrets status failed"
old="$(grep DOTSEC_API_TOKEN "${WS}/${TARGET}/.env.secrets")"
"$DOTSEC" rotate "$TARGET" token >/dev/null
[ "$old" != "$(grep DOTSEC_API_TOKEN "${WS}/${TARGET}/.env.secrets")" ] && ok "rotate token works" || ko "rotate token failed"
[ "$(stat -c '%a' "${WS}/${TARGET}/.env.secrets" 2>/dev/null)" = "600" ] && ok ".env.secrets still 600 after rotate" || ko "perms changed after rotate"

# [6] dashboard up/down
echo "[6] board up/down"
"$DOTSEC" board up >/dev/null 2>&1
docker ps --format '{{.Names}}' | grep -q dotsec-homer && ok "homer running" || ko "homer not running"
if have curl; then
    sleep 2
    code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${HOMER_PORT}" 2>/dev/null || echo 000)"
    [ "$code" = "200" ] && ok "dashboard responds" || ko "dashboard no response (${code})"
fi
"$DOTSEC" board down >/dev/null 2>&1

echo ""
echo "=== ${pass} passed, ${fail} failed ==="
[ "$fail" -eq 0 ]
