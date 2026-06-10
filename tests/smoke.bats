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

@test "__dotsec_load_global is set -e safe with no exegol container" {
    run env DOTSEC_HOME="$DOTSEC_HOME" bash -euo pipefail -c '
        DOTSEC_CONFIG=$(mktemp -d)
        docker() { :; }   # stub: no output, returns 0 → no container detected
        source "$DOTSEC_HOME/lib/ui.sh"
        source "$DOTSEC_HOME/lib/core.sh"
        unset EXEGOL_CONTAINER
        __dotsec_load_global
        echo REACHED
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *REACHED* ]]
}

@test "__dotsec_load_global re-detects when the configured container is gone" {
    run env DOTSEC_HOME="$DOTSEC_HOME" bash -euo pipefail -c '
        DOTSEC_CONFIG=$(mktemp -d)
        docker() {
            case "$1" in
                container) [[ "$2" == "inspect" ]] && return 1 ;;  # configured one gone
                ps) echo "exegol-a" ;;                              # a running exegol exists
            esac
            return 0
        }
        source "$DOTSEC_HOME/lib/ui.sh"
        source "$DOTSEC_HOME/lib/core.sh"
        EXEGOL_CONTAINER="exegol-dead"
        __dotsec_load_global
        echo "GOT=$EXEGOL_CONTAINER"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"GOT=exegol-a"* ]]
}

@test "dotsec list exits 0 when engagements exist" {
    local ws cfg
    ws="$(mktemp -d)"; cfg="$(mktemp -d)"
    mkdir -p "$ws/acme"
    printf 'export DOMAIN="acme.com"\n' > "$ws/acme/.env"
    run env WORKSPACE_ROOT="$ws" DOTSEC_CONFIG="$cfg" "$DOTSEC_BIN" list
    rm -rf "$ws" "$cfg"
    [ "$status" -eq 0 ]
    [[ "$output" == *acme* ]]
}

@test "dotsec rotate ssh aborts cleanly on closed stdin (EOF)" {
    local ws cfg
    ws="$(mktemp -d)"; cfg="$(mktemp -d)"
    bash -c "source '$DOTSEC_HOME/lib/ui.sh'; source '$DOTSEC_HOME/lib/core.sh'; source '$DOTSEC_HOME/lib/secrets.sh'; secrets_init '$ws/acme'" >/dev/null 2>&1
    run env WORKSPACE_ROOT="$ws" DOTSEC_CONFIG="$cfg" "$DOTSEC_BIN" rotate acme ssh </dev/null
    rm -rf "$ws" "$cfg"
    [ "$status" -eq 0 ]
    [[ "$output" == *Aborted* ]]
}
