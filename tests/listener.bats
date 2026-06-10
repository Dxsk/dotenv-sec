#!/usr/bin/env bats
load test_helper

@test "oob_logger logs method, path and body of a hit" {
    command -v python3 >/dev/null || skip "python3 missing"
    command -v curl >/dev/null || skip "curl missing"
    LOG="$(mktemp)"
    OOB_LOG="$LOG" OOB_BIND_PORT=18099 python3 "${DOTSEC_HOME}/listener/oob_logger.py" &
    pid=$!
    for _ in 1 2 3 4 5; do curl -s "http://127.0.0.1:18099/" >/dev/null 2>&1 && break; sleep 0.3; done
    curl -s -X POST -d 'pwned123' "http://127.0.0.1:18099/cb?x=1" >/dev/null 2>&1
    kill "$pid" 2>/dev/null || true
    run cat "$LOG"; rm -f "$LOG"
    [[ "$output" == *"POST /cb?x=1"* ]]
    [[ "$output" == *"pwned123"* ]]
}

@test "listener up runs compose (dotsec-oob) and starts the ssh tunnel" {
    WS="$(mktemp -d)"; logf="$(mktemp)"
    run env PATH="${DOTSEC_HOME}/tests/stubs:$PATH" SSH_STUB_LOG="$logf" \
        DOCKER_STUB_LOG="$logf" WORKSPACE="$WS" TARGET=acme OOB_PORT=19996 OOB_TUNNEL_WAIT=1 \
        "$DOTSEC_BIN" listener up
    grep -q 'compose' "$logf"
    grep -q 'dotsec-oob' "$logf"
    grep -q -- '-R 80:localhost:19996' "$logf"
    rm -rf "$WS" "$logf"
}

@test "listener up --no-tunnel skips ssh" {
    WS="$(mktemp -d)"; logf="$(mktemp)"
    run env PATH="${DOTSEC_HOME}/tests/stubs:$PATH" SSH_STUB_LOG="$logf" \
        DOCKER_STUB_LOG="$logf" WORKSPACE="$WS" TARGET=acme OOB_PORT=19996 OOB_TUNNEL_WAIT=1 \
        "$DOTSEC_BIN" listener up --no-tunnel
    grep -q 'compose' "$logf"
    ! grep -q 'ssh ' "$logf"
    rm -rf "$WS" "$logf"
}
