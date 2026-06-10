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
