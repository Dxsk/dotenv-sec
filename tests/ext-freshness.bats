#!/usr/bin/env bats
load test_helper

SCRIPT="$DOTSEC_HOME/.github/scripts/check-ext-versions.sh"

# curl stub : répond selon l'URL à partir des variables STUB_GH_TAG / STUB_WS_VER,
# ou échoue (exit 22) si STUB_FAIL=1. Écrit dans <dir>/bin/curl.
_mk_curl_stub() {
    local d="$1"
    mkdir -p "$d/bin"
    cat > "$d/bin/curl" <<'EOF'
#!/usr/bin/env bash
url="${@: -1}"
[ "${STUB_FAIL:-0}" = "1" ] && exit 22
case "$url" in
    *api.github.com*releases/latest*) printf '{"tag_name":"%s"}\n' "${STUB_GH_TAG:-v1.0.0}";;
    *api.github.com*/tags*)           printf '[{"name":"%s"}]\n'   "${STUB_GH_TAG:-v1.0.0}";;
    *clients2.google.com*)            printf '<updatecheck status="ok" version="%s"/>\n' "${STUB_WS_VER:-1.0.0}";;
    *) exit 22;;
esac
EOF
    chmod +x "$d/bin/curl"
}

@test "github extension up-to-date → exit 0" {
    local d; d="$(mktemp -d)"
    _mk_curl_stub "$d"
    printf 'alpha | github | owner/alpha | v1.2.3 | x | .\n' > "$d/m.list"
    run env PATH="$d/bin:$PATH" EXT_MANIFEST="$d/m.list" STUB_GH_TAG="v1.2.3" \
        bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"à jour"* ]]
}

@test "github extension outdated → exit 1 + report écrit" {
    local d; d="$(mktemp -d)"
    _mk_curl_stub "$d"
    printf 'alpha | github | owner/alpha | v1.2.3 | x | .\n' > "$d/m.list"
    run env PATH="$d/bin:$PATH" EXT_MANIFEST="$d/m.list" STUB_GH_TAG="v1.4.0" \
        EXT_OUTDATED_FILE="$d/out.md" bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"v1.2.3"* ]]
    [[ "$output" == *"v1.4.0"* ]]
    grep -q "alpha" "$d/out.md"
    grep -q "v1.4.0" "$d/out.md"
}

@test "webstore extension outdated → exit 1" {
    local d; d="$(mktemp -d)"
    _mk_curl_stub "$d"
    printf 'beta | webstore | abcdefghijklmnop | 2.1.12 | x |\n' > "$d/m.list"
    run env PATH="$d/bin:$PATH" EXT_MANIFEST="$d/m.list" STUB_WS_VER="2.2.0" \
        bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"2.2.0"* ]]
}

@test "webstore extension up-to-date → exit 0" {
    local d; d="$(mktemp -d)"
    _mk_curl_stub "$d"
    printf 'beta | webstore | abcdefghijklmnop | 6.12.2 | x |\n' > "$d/m.list"
    run env PATH="$d/bin:$PATH" EXT_MANIFEST="$d/m.list" STUB_WS_VER="6.12.2" \
        bash "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "fetch error reste lenient par défaut → exit 0" {
    local d; d="$(mktemp -d)"
    _mk_curl_stub "$d"
    printf 'alpha | github | owner/alpha | v1.0.0 | x | .\n' > "$d/m.list"
    run env PATH="$d/bin:$PATH" EXT_MANIFEST="$d/m.list" STUB_FAIL="1" \
        bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"erreurs"* ]]
}

@test "fetch error en mode strict → exit 2" {
    local d; d="$(mktemp -d)"
    _mk_curl_stub "$d"
    printf 'alpha | github | owner/alpha | v1.0.0 | x | .\n' > "$d/m.list"
    run env PATH="$d/bin:$PATH" EXT_MANIFEST="$d/m.list" STUB_FAIL="1" EXT_STRICT="1" \
        bash "$SCRIPT"
    [ "$status" -eq 2 ]
}

@test "lignes commentaires et vides ignorées" {
    local d; d="$(mktemp -d)"
    _mk_curl_stub "$d"
    printf '# commentaire\n\nalpha | github | owner/alpha | v1.0.0 | x | .\n' > "$d/m.list"
    run env PATH="$d/bin:$PATH" EXT_MANIFEST="$d/m.list" STUB_GH_TAG="v1.0.0" \
        bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"à jour: "* ]]
}

@test "manifest introuvable → exit 2" {
    run env EXT_MANIFEST="/nonexistent/path.list" bash "$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"introuvable"* ]]
}

@test "manifest réel du repo est parsable (smoke, réseau stubé)" {
    local d; d="$(mktemp -d)"
    _mk_curl_stub "$d"
    # Renvoie systématiquement les versions épinglées → tout « à jour ».
    run env PATH="$d/bin:$PATH" STUB_GH_TAG="v0.0.0" STUB_WS_VER="0.0.0" \
        bash "$SCRIPT"
    # v0.0.0 < tout ref épinglé → jamais « plus récent » → exit 0.
    [ "$status" -eq 0 ]
    [[ "$output" == *"js-recon-buddy"* ]]
    [[ "$output" == *"wappalyzer"* ]]
}
