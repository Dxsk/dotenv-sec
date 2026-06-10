#!/usr/bin/env bats
load test_helper

# Build a github-like tarball fixture (root dir stripped by --strip-components=1)
# plus a curl stub that serves it via the -o flag. Writes into <dir>.
_mk_github_fixture() {
    local d="$1"
    mkdir -p "$d/src/alpha-1.0"
    echo '{"name":"alpha","manifest_version":3,"version":"1.0"}' > "$d/src/alpha-1.0/manifest.json"
    tar -czf "$d/dl.tar.gz" -C "$d/src" alpha-1.0
    mkdir -p "$d/bin"
    cat > "$d/bin/curl" <<EOF
#!/usr/bin/env bash
out=""
while [ \$# -gt 0 ]; do case "\$1" in -o) out="\$2"; shift 2;; *) shift;; esac; done
cp "$d/dl.tar.gz" "\$out"
EOF
    chmod +x "$d/bin/curl"
}

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

@test "github provider extracts unpacked extension and verifies sha256" {
    local d; d="$(mktemp -d)"
    _mk_github_fixture "$d"
    local want; want="$(sha256sum "$d/dl.tar.gz" | cut -d' ' -f1)"
    run env PATH="$d/bin:$PATH" DOTSEC_EXT_DIR="$d/ext" bash -c \
        "source '$DOTSEC_HOME/lib/ui.sh'; source '$DOTSEC_HOME/lib/ext.sh'; __ext_fetch_github alpha owner/alpha v1.0 '$want' ."
    [ "$status" -eq 0 ]
    [ -f "$d/ext/alpha/manifest.json" ]
    [ -f "$d/ext/alpha/.dotsec-version" ]
}

@test "github provider rejects sha256 mismatch" {
    local d; d="$(mktemp -d)"
    _mk_github_fixture "$d"
    run env PATH="$d/bin:$PATH" DOTSEC_EXT_DIR="$d/ext" bash -c \
        "source '$DOTSEC_HOME/lib/ui.sh'; source '$DOTSEC_HOME/lib/ext.sh'; __ext_fetch_github alpha owner/alpha v1.0 'deadbeefwrong' ."
    [ "$status" -ne 0 ]
    [ ! -f "$d/ext/alpha/manifest.json" ]
}
