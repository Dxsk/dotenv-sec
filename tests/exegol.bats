#!/usr/bin/env bats
load test_helper

setup() {
    DEST="$(mktemp -d)"
    export MYRES_DIR="$DEST" DOTSEC_HOME="$DOTSEC_HOME"
}
teardown() { rm -rf "$DEST"; }

run_deploy() { bash "${DOTSEC_HOME}/exegol/my-resources/deploy.sh"; }

@test "deploy creates a delimited dotsec block in aliases" {
    run_deploy
    grep -qF "# >>> dotsec >>>" "$DEST/setup/zsh/aliases"
    grep -qF "# <<< dotsec <<<" "$DEST/setup/zsh/aliases"
}
@test "deploy is idempotent (single block after two runs)" {
    run_deploy
    run_deploy
    [ "$(grep -cF '# >>> dotsec >>>' "$DEST/setup/zsh/aliases")" -eq 1 ]
}
@test "deploy preserves pre-existing user content in aliases" {
    mkdir -p "$DEST/setup/zsh"
    printf "alias myown='echo hi'\n" > "$DEST/setup/zsh/aliases"
    run_deploy
    grep -q "myown" "$DEST/setup/zsh/aliases"
    grep -qF "# >>> dotsec >>>" "$DEST/setup/zsh/aliases"
}
@test "dl sources an engagement env into the shell" {
    ws="$(mktemp -d)"
    mkdir -p "$ws/acme"
    printf 'export TARGET="acme"\nexport DOMAIN="acme.com"\n' > "$ws/acme/.env"
    run bash -c "WORKSPACE_ROOT='$ws'; source '${DOTSEC_HOME}/exegol/my-resources/bin/dl' acme 2>/dev/null; echo \"GOT=\$DOMAIN\""
    rm -rf "$ws"
    [[ "$output" == *"GOT=acme.com"* ]]
}
@test "dl refuses an env with command substitution" {
    ws="$(mktemp -d)"
    mkdir -p "$ws/acme"
    printf 'export X=$(id)\n' > "$ws/acme/.env"
    run bash -c "WORKSPACE_ROOT='$ws'; source '${DOTSEC_HOME}/exegol/my-resources/bin/dl' acme; echo done"
    rm -rf "$ws"
    [[ "$output" != *"done"* ]] || [[ "$output" == *"refus"* ]]
}

@test "recon scripts fail fast when DOMAIN is unset" {
    for s in recon-subs recon-alive recon-crawl recon-sourcemaps recon-full; do
        run env -u DOMAIN bash "${DOTSEC_HOME}/exegol/my-resources/bin/$s"
        [ "$status" -ne 0 ] || { echo "$s did not guard DOMAIN"; false; }
    done
}
