#!/usr/bin/env bats
load test_helper

setup() {
    source "${DOTSEC_HOME}/lib/ui.sh"
    source "${DOTSEC_HOME}/lib/core.sh"
    WS="$(mktemp -d)"; export WORKSPACE_ROOT="$WS"
    export DOTSEC_HOME
    source "${DOTSEC_HOME}/lib/dashboard.sh"
}
teardown() { rm -rf "$WS" "${DOTSEC_HOME}/homer/config.yml"; }

@test "__homer_gen_config uses custom PROXY_PORT/WEB_PORT" {
    mkdir -p "$WS/acme"
    printf 'export DOMAIN="acme.com"\n' > "$WS/acme/.env"
    PROXY_PORT=12345 WEB_PORT=12346 __homer_gen_config >/dev/null
    grep -q "127.0.0.1:12345" "${DOTSEC_HOME}/homer/config.yml"
    grep -q "127.0.0.1:12346" "${DOTSEC_HOME}/homer/config.yml"
}

# ── Docker-stub tests (CI-safe, no daemon required) ──────────────────────────

@test "proxy_up builds compose command with correct project name" {
    source "${DOTSEC_HOME}/lib/proxy.sh"
    local stub_log
    stub_log="$(mktemp)"

    local ws
    ws="$(mktemp -d)"
    # Provide MITMWEB_PASS so proxy_up doesn't need /dev/urandom redirect
    printf 'MITMWEB_PASS="testpass"\n' > "${ws}/.env.secrets"

    DOCKER_STUB_LOG="$stub_log" \
    PATH="${DOTSEC_HOME}/tests/stubs:$PATH" \
    TARGET="stubtest" \
    WORKSPACE="$ws" \
    PROXY_PORT=19999 \
    WEB_PORT=19998 \
    proxy_up >/dev/null 2>&1

    grep -q "compose" "$stub_log"
    grep -q "dotsec-stubtest" "$stub_log"

    rm -f "$stub_log"
    rm -rf "$ws"
}

@test "cmd_dashboard up generates homer/config.yml and calls compose" {
    local stub_log
    stub_log="$(mktemp)"

    mkdir -p "$WS/pentest"
    printf 'DOMAIN="pentest.local"\n' > "$WS/pentest/.env"

    DOCKER_STUB_LOG="$stub_log" \
    PATH="${DOTSEC_HOME}/tests/stubs:$PATH" \
    HOMER_PORT=19997 \
    cmd_dashboard up >/dev/null 2>&1

    [[ -f "${DOTSEC_HOME}/homer/config.yml" ]]
    grep -q "compose" "$stub_log"

    rm -f "$stub_log"
}
