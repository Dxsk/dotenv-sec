#!/usr/bin/env bats
load test_helper

@test "dotsec help exits 0 and shows usage" {
    run "$DOTSEC_BIN" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pentest environment launcher"* ]]
    [[ "$output" == *"ENGAGEMENT"* ]]
}

@test "dotsec info exits 0 and shows config keys" {
    run "$DOTSEC_BIN" info
    [ "$status" -eq 0 ]
    [[ "$output" == *"TARGET"* ]]
    [[ "$output" == *"DOTSEC_HOME"* ]]
}

@test "unknown command shows error" {
    run "$DOTSEC_BIN" definitely-not-a-command
    [[ "$output" == *"Unknown command"* ]]
}
