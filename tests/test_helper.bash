# Helper commun aux tests bats dotsec
DOTSEC_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DOTSEC_HOME
DOTSEC_BIN="${DOTSEC_HOME}/bin/dotsec"

# Workspace temporaire isolé par test
setup_workspace() {
    TEST_WS="$(mktemp -d)"
    export WORKSPACE_ROOT="$TEST_WS"
}
teardown_workspace() {
    [[ -n "${TEST_WS:-}" ]] && rm -rf "$TEST_WS"
}
