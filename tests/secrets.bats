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
    echo "DIAG actual length=${#output}" >&2   # shown by bats only on failure
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

@test "secrets_init creates .env.secrets (600) with the three keys" {
    secrets_init "$TMP"
    [ "$(stat -c '%a' "${TMP}/.env.secrets")" = "600" ]
    grep -q '^export DOTSEC_SESSION_SECRET="' "${TMP}/.env.secrets"
    grep -q '^export DOTSEC_API_TOKEN="'      "${TMP}/.env.secrets"
    grep -q '^export MITMWEB_PASS="'          "${TMP}/.env.secrets"
}
@test "secrets_init creates ssh key 600 and pub 644" {
    secrets_init "$TMP"
    [ -f "${TMP}/keys/id_ed25519" ]
    [ "$(stat -c '%a' "${TMP}/keys/id_ed25519")" = "600" ]
    [ "$(stat -c '%a' "${TMP}/keys/id_ed25519.pub")" = "644" ]
    [ "$(stat -c '%a' "${TMP}/keys")" = "700" ]
}
@test "secrets_init is idempotent (values unchanged on 2nd call)" {
    secrets_init "$TMP"
    before="$(grep '^export DOTSEC_SESSION_SECRET=' "${TMP}/.env.secrets")"
    before_key="$(cat "${TMP}/keys/id_ed25519")"
    secrets_init "$TMP"
    after="$(grep '^export DOTSEC_SESSION_SECRET=' "${TMP}/.env.secrets")"
    after_key="$(cat "${TMP}/keys/id_ed25519")"
    [ "$before" = "$after" ]
    [ "$before_key" = "$after_key" ]
}
@test "secrets_init survives set -e (no premature abort)" {
    run bash -c "set -euo pipefail; source '${DOTSEC_HOME}/lib/ui.sh'; source '${DOTSEC_HOME}/lib/secrets.sh'; ws=\$(mktemp -d); secrets_init \"\$ws\"; echo REACHED_END; rm -rf \"\$ws\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"REACHED_END"* ]]
}

@test "secrets_rotate token changes token values" {
    secrets_init "$TMP"
    old="$(grep '^export DOTSEC_API_TOKEN=' "${TMP}/.env.secrets")"
    secrets_rotate "$TMP" token
    new="$(grep '^export DOTSEC_API_TOKEN=' "${TMP}/.env.secrets")"
    [ "$old" != "$new" ]
}
@test "secrets_rotate mitmweb changes only the password" {
    secrets_init "$TMP"
    old_tok="$(grep '^export DOTSEC_API_TOKEN=' "${TMP}/.env.secrets")"
    old_pw="$(grep '^export MITMWEB_PASS=' "${TMP}/.env.secrets")"
    secrets_rotate "$TMP" mitmweb
    [ "$old_tok" = "$(grep '^export DOTSEC_API_TOKEN=' "${TMP}/.env.secrets")" ]
    [ "$old_pw" != "$(grep '^export MITMWEB_PASS=' "${TMP}/.env.secrets")" ]
}
@test "secrets_rotate ssh regenerates the key" {
    secrets_init "$TMP"
    old="$(cat "${TMP}/keys/id_ed25519")"
    secrets_rotate "$TMP" ssh
    [ "$old" != "$(cat "${TMP}/keys/id_ed25519")" ]
}
@test "secrets_rotate ca removes existing CA files" {
    secrets_init "$TMP"
    touch "${TMP}/proxy/certs/mitmproxy-ca-cert.pem"
    secrets_rotate "$TMP" ca
    [ ! -f "${TMP}/proxy/certs/mitmproxy-ca-cert.pem" ]
}
@test "secrets_rotate rejects unknown type" {
    secrets_init "$TMP"
    run secrets_rotate "$TMP" bogus
    [ "$status" -ne 0 ]
}

@test "secrets_show never prints token values in clear" {
    secrets_init "$TMP"
    tok="$(grep '^export DOTSEC_API_TOKEN=' "${TMP}/.env.secrets" | sed -E 's/.*="(.*)"/\1/')"
    run secrets_show "$TMP"
    [ "$status" -eq 0 ]
    [[ "$output" != *"$tok"* ]]
}
@test "secrets_show reports presence and ssh fingerprint" {
    secrets_init "$TMP"
    run secrets_show "$TMP"
    [[ "$output" == *"DOTSEC_API_TOKEN"* ]]
    [[ "$output" == *"SSH"* ]]
    [[ "$output" == *"SHA256:"* ]]
}
