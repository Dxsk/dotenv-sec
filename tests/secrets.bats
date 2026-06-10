#!/usr/bin/env bats
load test_helper

setup() {
    source "${DOTSEC_HOME}/lib/ui.sh"
    source "${DOTSEC_HOME}/lib/secrets.sh"
    TMP="$(mktemp -d)"
}
teardown() { rm -rf "$TMP"; }

@test "__sec_rand produces requested length, alnum only" {
    run __sec_rand 24
    [ "$status" -eq 0 ]
    [ "${#output}" -eq 24 ]
    [[ "$output" =~ ^[A-Za-z0-9]+$ ]]
}
@test "__sec_env_set adds then replaces idempotently" {
    f="${TMP}/.env.secrets"
    __sec_env_set "$f" FOO bar
    grep -q '^export FOO="bar"$' "$f"
    __sec_env_set "$f" FOO baz
    grep -q '^export FOO="baz"$' "$f"
    [ "$(grep -c '^export FOO=' "$f")" -eq 1 ]
}
@test "__sec_guard_envfile rejects command substitution" {
    f="${TMP}/bad"; printf 'export X=$(id)\n' > "$f"
    run __sec_guard_envfile "$f"; [ "$status" -ne 0 ]
}
@test "__sec_guard_envfile rejects backticks" {
    f="${TMP}/bad2"; printf 'export X=`id`\n' > "$f"
    run __sec_guard_envfile "$f"; [ "$status" -ne 0 ]
}
@test "__sec_guard_envfile accepts clean file" {
    f="${TMP}/ok"; printf 'export X="plain"\n' > "$f"
    run __sec_guard_envfile "$f"; [ "$status" -eq 0 ]
}
@test "__sec_chmod_strict sets 600 on files, 700 on dirs" {
    touch "${TMP}/f"; mkdir "${TMP}/d"
    __sec_chmod_strict "${TMP}/f" "${TMP}/d"
    [ "$(stat -c '%a' "${TMP}/f")" = "600" ]
    [ "$(stat -c '%a' "${TMP}/d")" = "700" ]
}
