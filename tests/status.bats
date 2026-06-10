#!/usr/bin/env bats
load test_helper

setup() {
    WS="$(mktemp -d)"; CFG="$(mktemp -d)"
    export WORKSPACE_ROOT="$WS" DOTSEC_CONFIG="$CFG"
    export PATH="${DOTSEC_HOME}/tests/stubs:$PATH"   # stub docker (ps → empty)
}
teardown() { rm -rf "$WS" "$CFG"; }

mk() { # mk <target> <domain>
    mkdir -p "$WS/$1/recon/loot"
    printf 'export TARGET="%s"\nexport DOMAIN="%s"\nexport PROXY_PORT="9999"\n' "$1" "$2" > "$WS/$1/.env"
}

@test "status with no engagements shows hint" {
    run "$DOTSEC_BIN" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"No engagements"* ]]
}

@test "status lists engagements with domain + stats + global header" {
    mk acme acme.com
    mk ghost ghost.com
    run "$DOTSEC_BIN" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"Global"* ]]
    [[ "$output" == *"acme"* ]]   && [[ "$output" == *"acme.com"* ]]
    [[ "$output" == *"ghost"* ]]  && [[ "$output" == *"ghost.com"* ]]
    [[ "$output" == *"Workspace"* ]]
    [[ "$output" == *"Proxy"* ]]
}

@test "status <target> shows only that engagement" {
    mk acme acme.com
    mk ghost ghost.com
    run "$DOTSEC_BIN" status acme
    [ "$status" -eq 0 ]
    [[ "$output" == *"acme"* ]]
    [[ "$output" != *"ghost"* ]]
}
