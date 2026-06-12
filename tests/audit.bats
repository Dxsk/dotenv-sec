#!/usr/bin/env bats
setup() {
    BIN="${BATS_TEST_DIRNAME}/../exegol/my-resources/bin"
    export PATH="${BATS_TEST_DIRNAME}/stubs:${PATH}"
    WS="$(mktemp -d)"; export WORKSPACE="$WS"
    mkdir -p "$WS/code"; echo 'eval(x)' > "$WS/code/a.js"
}
teardown() { rm -rf "$WS"; }

@test "audit-sinks writes sinks.json from semgrep" {
    run "$BIN/audit-sinks"
    [ "$status" -eq 0 ]
    [ -f "$WS/scans/code/sinks.json" ]
    grep -q "js-eval" "$WS/scans/code/sinks.json"
}

@test "audit-sinks errors on empty code dir" {
    rm -rf "$WS/code"; mkdir -p "$WS/code"
    run "$BIN/audit-sinks"
    [ "$status" -ne 0 ]
}

@test "audit-endpoints writes endpoints.json from semgrep" {
    cp "${BATS_TEST_DIRNAME}/../exegol/my-resources/audit-rules/endpoints.yml" /dev/null 2>/dev/null || true
    export MYRES="${BATS_TEST_DIRNAME}/../exegol/my-resources"
    run "$BIN/audit-endpoints"
    [ "$status" -eq 0 ]
    [ -f "$WS/scans/code/endpoints.json" ]
}
