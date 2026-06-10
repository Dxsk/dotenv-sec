#!/usr/bin/env bats
# Router smoke tests — Docker-free command paths only.
# Docker-dependent verbs (new, proxy up/down, browser, board up, exegol,
# spawn, tmux, stop, restart) need a manual integration smoke; not covered here.
load test_helper

setup() {
    WS="$(mktemp -d)"; CFG="$(mktemp -d)"
    export WORKSPACE_ROOT="$WS" DOTSEC_CONFIG="$CFG"
}
teardown() { rm -rf "$WS" "$CFG"; }

# Create an engagement workspace with generated secrets (no Docker).
_mk_engagement() {
    bash -c "source '$DOTSEC_HOME/lib/ui.sh'; source '$DOTSEC_HOME/lib/core.sh'; source '$DOTSEC_HOME/lib/secrets.sh'; secrets_init '$WS/$1'" >/dev/null 2>&1
    printf 'export TARGET="%s"\nexport DOMAIN="%s.com"\n' "$1" "$1" > "$WS/$1/.env"
}

@test "no argument prints usage" {
    run "$DOTSEC_BIN"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pentest environment launcher"* ]]
}

@test "load on a missing engagement errors out" {
    run "$DOTSEC_BIN" load ghost
    [ "$status" -ne 0 ]
    [[ "$output" == *"dotsec load needs the shell function"* ]]
}

@test "env on a missing engagement errors out" {
    run "$DOTSEC_BIN" env ghost
    [ "$status" -ne 0 ]
    [[ "$output" == *"No .env"* ]]
}

@test "unload reports vars unset" {
    run "$DOTSEC_BIN" unload
    [ "$status" -eq 0 ]
    [[ "$output" == *"unset"* ]]
}

@test "secrets without target shows usage" {
    run "$DOTSEC_BIN" secrets
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage: dotsec secrets"* ]]
}

@test "secrets shows masked status for an engagement" {
    _mk_engagement acme
    run "$DOTSEC_BIN" secrets acme
    [ "$status" -eq 0 ]
    [[ "$output" == *"DOTSEC_API_TOKEN"* ]]
    [[ "$output" == *"SSH"* ]]
    # never leaks the actual token value
    tok="$(grep -oE 'DOTSEC_API_TOKEN="[^"]+"' "$WS/acme/.env.secrets" | cut -d'"' -f2)"
    [[ "$output" != *"$tok"* ]]
}

@test "rotate without target shows usage" {
    run "$DOTSEC_BIN" rotate
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage: dotsec rotate"* ]]
}

@test "rotate token regenerates without prompting" {
    _mk_engagement acme
    old="$(grep DOTSEC_API_TOKEN "$WS/acme/.env.secrets")"
    run "$DOTSEC_BIN" rotate acme token
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rotated"* ]]
    [ "$old" != "$(grep DOTSEC_API_TOKEN "$WS/acme/.env.secrets")" ]
}

@test "env emits export lines for an engagement (clean stdout)" {
    ws="$(mktemp -d)"; cfg="$(mktemp -d)"
    mkdir -p "$ws/acme"
    printf 'export TARGET="acme"\nexport DOMAIN="acme.com"\n' > "$ws/acme/.env"
    printf 'export MITMWEB_PASS="secret123"\n' > "$ws/acme/.env.secrets"
    run env WORKSPACE_ROOT="$ws" DOTSEC_CONFIG="$cfg" "$DOTSEC_BIN" env acme
    rm -rf "$ws" "$cfg"
    [ "$status" -eq 0 ]
    [[ "$output" == *'export TARGET="acme"'* ]]
    [[ "$output" == *'export MITMWEB_PASS="secret123"'* ]]
    [[ "$output" != *'[!]'* ]]
}
@test "env rejects command substitution in .env" {
    ws="$(mktemp -d)"; cfg="$(mktemp -d)"
    mkdir -p "$ws/acme"
    printf 'export X=$(id)\n' > "$ws/acme/.env"
    run env WORKSPACE_ROOT="$ws" DOTSEC_CONFIG="$cfg" "$DOTSEC_BIN" env acme
    rm -rf "$ws" "$cfg"
    [ "$status" -ne 0 ]
}
@test "env without target shows usage" {
    run "$DOTSEC_BIN" env
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage: dotsec env"* ]]
}

@test "zsh dotsec() function exports vars into the shell" {
    command -v zsh >/dev/null || skip "zsh not installed"
    ws="$(mktemp -d)"; cfg="$(mktemp -d)"
    mkdir -p "$ws/acme"
    printf 'export TARGET="acme"\nexport DOMAIN="acme.com"\n' > "$ws/acme/.env"
    run env PATH="${DOTSEC_HOME}/bin:$PATH" WORKSPACE_ROOT="$ws" DOTSEC_CONFIG="$cfg" \
        DOTSEC_HOME="$DOTSEC_HOME" zsh -c \
        "source '${DOTSEC_HOME}/config/shellrc.zsh'; dotsec load acme; print \"GOT=\$TARGET\""
    rm -rf "$ws" "$cfg"
    [[ "$output" == *"GOT=acme"* ]]
}
@test "zsh dotsec() delegates other commands to the binary" {
    command -v zsh >/dev/null || skip "zsh not installed"
    run env PATH="${DOTSEC_HOME}/bin:$PATH" DOTSEC_HOME="$DOTSEC_HOME" zsh -c \
        "source '${DOTSEC_HOME}/config/shellrc.zsh'; dotsec help"
    [[ "$output" == *"Pentest environment launcher"* ]]
}

@test "proxy with a bad subcommand shows usage" {
    run "$DOTSEC_BIN" proxy bogus
    [[ "$output" == *"proxy up|down|status|logs"* ]]
}

@test "board with a bad subcommand shows usage" {
    run "$DOTSEC_BIN" board bogus
    [[ "$output" == *"board up|down|reload|status"* ]]
}
