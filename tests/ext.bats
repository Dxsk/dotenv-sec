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

# Build a fake .crx (12-byte Cr24 header + a real zip) plus a curl stub.
_mk_crx_fixture() {
    local d="$1"
    mkdir -p "$d/src"
    echo '{"name":"beta","manifest_version":3,"version":"2.1"}' > "$d/src/manifest.json"
    ( cd "$d/src" && zip -q "$d/e.zip" manifest.json )
    printf 'Cr24\x03\x00\x00\x00\x00\x00\x00\x00' > "$d/e.crx"
    cat "$d/e.zip" >> "$d/e.crx"
    mkdir -p "$d/bin"
    cat > "$d/bin/curl" <<EOF
#!/usr/bin/env bash
out=""
while [ \$# -gt 0 ]; do case "\$1" in -o) out="\$2"; shift 2;; *) shift;; esac; done
cp "$d/e.crx" "\$out"
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

@test "webstore provider extracts crx and verifies sha256" {
    command -v zip unzip >/dev/null || skip "zip/unzip not installed"
    local d; d="$(mktemp -d)"
    _mk_crx_fixture "$d"
    local want; want="$(sha256sum "$d/e.crx" | cut -d' ' -f1)"
    run env PATH="$d/bin:$PATH" DOTSEC_EXT_DIR="$d/ext" bash -c \
        "source '$DOTSEC_HOME/lib/ui.sh'; source '$DOTSEC_HOME/lib/ext.sh'; __ext_fetch_webstore beta abcdefghijklmnop 2.1 '$want'"
    [ "$status" -eq 0 ]
    [ -f "$d/ext/beta/manifest.json" ]
    [ -f "$d/ext/beta/.dotsec-version" ]
}

@test "webstore provider rejects sha256 mismatch" {
    command -v zip unzip >/dev/null || skip "zip/unzip not installed"
    local d; d="$(mktemp -d)"
    _mk_crx_fixture "$d"
    run env PATH="$d/bin:$PATH" DOTSEC_EXT_DIR="$d/ext" bash -c \
        "source '$DOTSEC_HOME/lib/ui.sh'; source '$DOTSEC_HOME/lib/ext.sh'; __ext_fetch_webstore beta abcdefghijklmnop 2.1 'wrongsha'"
    [ "$status" -ne 0 ]
    [ ! -f "$d/ext/beta/manifest.json" ]
}

@test "ext sync installs extensions from manifest" {
    local d; d="$(mktemp -d)"
    _mk_github_fixture "$d"
    local want; want="$(sha256sum "$d/dl.tar.gz" | cut -d' ' -f1)"
    printf 'alpha | github | owner/alpha | v1.0 | %s | .\n' "$want" > "$d/m.list"
    run env PATH="$d/bin:$PATH" DOTSEC_EXT_DIR="$d/ext" DOTSEC_EXT_MANIFEST="$d/m.list" \
        bash -c "source '$DOTSEC_HOME/lib/ui.sh'; source '$DOTSEC_HOME/lib/ext.sh'; ext_sync"
    [ "$status" -eq 0 ]
    [ -f "$d/ext/alpha/manifest.json" ]
}

@test "ext sync is idempotent (skips up-to-date)" {
    local d; d="$(mktemp -d)"
    _mk_github_fixture "$d"
    local want; want="$(sha256sum "$d/dl.tar.gz" | cut -d' ' -f1)"
    printf 'alpha | github | owner/alpha | v1.0 | %s | .\n' "$want" > "$d/m.list"
    env PATH="$d/bin:$PATH" DOTSEC_EXT_DIR="$d/ext" DOTSEC_EXT_MANIFEST="$d/m.list" \
        bash -c "source '$DOTSEC_HOME/lib/ui.sh'; source '$DOTSEC_HOME/lib/ext.sh'; ext_sync" >/dev/null 2>&1
    run env PATH="$d/bin:$PATH" DOTSEC_EXT_DIR="$d/ext" DOTSEC_EXT_MANIFEST="$d/m.list" \
        bash -c "source '$DOTSEC_HOME/lib/ui.sh'; source '$DOTSEC_HOME/lib/ext.sh'; ext_sync"
    [ "$status" -eq 0 ]
    [[ "$output" == *up-to-date* ]]
}

@test "managed-bookmarks.json is valid JSON with CyberChef" {
    command -v python3 >/dev/null || skip "python3 not installed"
    run python3 -m json.tool "$DOTSEC_HOME/chromium/managed-bookmarks.json"
    [ "$status" -eq 0 ]
    [[ "$output" == *ManagedBookmarks* ]]
    [[ "$output" == *CyberChef* ]]
}

@test "cmd_browser mounts extensions dir and bookmarks policy" {
    local d; d="$(mktemp -d)"
    mkdir -p "$d/ext/foo" "$d/bin" "$d/ws/smoke/proxy/certs" "$d/cfg"
    echo '{}' > "$d/ext/foo/manifest.json"
    cat > "$d/bin/docker" <<EOF
#!/usr/bin/env bash
case "\$1" in
  ps)  echo "mitmproxy-smoke";;   # proxy "running" → skip proxy_up
  run) printf '%s\n' "\$*" > "$d/run.args";;
esac
exit 0
EOF
    chmod +x "$d/bin/docker"
    run env PATH="$d/bin:$PATH" DOTSEC_EXT_DIR="$d/ext" WORKSPACE_ROOT="$d/ws" DOTSEC_CONFIG="$d/cfg" \
        "$DOTSEC_BIN" browser smoke
    [ "$status" -eq 0 ]
    [ -f "$d/run.args" ]
    grep -q -- "/extensions:ro" "$d/run.args"
    grep -q -- "managed/dotsec.json:ro" "$d/run.args"
}
