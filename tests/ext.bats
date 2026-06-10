#!/usr/bin/env bats
load test_helper

@test "ext list prints extension names from manifest" {
    run env DOTSEC_EXT_MANIFEST="$DOTSEC_HOME/tests/fixtures/ext/sample.list" \
        "$DOTSEC_BIN" ext list
    [ "$status" -eq 0 ]
    [[ "$output" == *alpha* ]]
    [[ "$output" == *beta* ]]
}

@test "ext with no subcommand shows usage" {
    run "$DOTSEC_BIN" ext
    [[ "$output" == *"ext sync|list"* ]]
}
