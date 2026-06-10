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
