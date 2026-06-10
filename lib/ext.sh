#!/usr/bin/env bash
# ─── lib/ext.sh ─── browser extension manager (sync/list) ──

__ext_manifest() {
    echo "${DOTSEC_EXT_MANIFEST:-${DOTSEC_HOME}/chromium/extensions.list}"
}

__ext_dir() {
    echo "${DOTSEC_EXT_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/dotenvsec/extensions}"
}

# Trim leading/trailing whitespace (pure bash, no xargs surprises on quotes).
__ext_trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# Parse the manifest, invoking <callback> with the 6 trimmed fields per entry.
# Manifest line: name | provider | source | ref | sha256 | subdir   (# = comment)
__ext_each() {
    local cb="$1" manifest name provider src ref sha subdir
    manifest="$(__ext_manifest)"
    if [[ ! -f "$manifest" ]]; then
        printf '%b\n' "${RED}[!] No manifest: ${manifest}${RESET}" >&2
        return 1
    fi
    while IFS='|' read -r name provider src ref sha subdir; do
        name="$(__ext_trim "${name:-}")"
        [[ -z "$name" || "$name" == \#* ]] && continue
        provider="$(__ext_trim "${provider:-}")"
        src="$(__ext_trim "${src:-}")"
        ref="$(__ext_trim "${ref:-}")"
        sha="$(__ext_trim "${sha:-}")"
        subdir="$(__ext_trim "${subdir:-}")"
        "$cb" "$name" "$provider" "$src" "$ref" "$sha" "$subdir"
    done < "$manifest"
}

__ext_list_one() {
    local name="$1" provider="$2" ref="$4"
    local state="${RED}missing${RESET}"
    [[ -f "$(__ext_dir)/${name}/manifest.json" ]] && state="${GREEN}ok${RESET}"
    printf '  %-18s %-9s %-12s %b\n' "$name" "$provider" "$ref" "$state"
}

ext_list() {
    printf '%b\n' "${DIM}Extensions dir: $(__ext_dir)${RESET}"
    __ext_each __ext_list_one
}

# __ext_fetch_github <name> <repo> <tag> <sha256> <subdir>
# Downloads the tag tarball, verifies sha256, extracts the unpacked extension
# (subdir, or repo root) into $DOTSEC_EXT_DIR/<name>/.
__ext_fetch_github() {
    local name="$1" repo="$2" tag="$3" want="$4" subdir="${5:-.}"
    local dir; dir="$(__ext_dir)"
    local url="https://github.com/${repo}/archive/refs/tags/${tag}.tar.gz"
    local tmp; tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    if ! curl -fsSL "$url" -o "$tmp/dl.tar.gz"; then
        printf '%b\n' "  ${RED}[!] download failed: ${url}${RESET}" >&2
        return 1
    fi
    local got; got="$(sha256sum "$tmp/dl.tar.gz" | cut -d' ' -f1)"
    if [[ -n "$want" && "$got" != "$want" ]]; then
        printf '%b\n' "  ${RED}[!] sha256 mismatch for ${name}${RESET}" >&2
        printf '%b\n' "      want ${want}" >&2
        printf '%b\n' "      got  ${got}" >&2
        return 1
    fi
    mkdir -p "$tmp/x"
    tar -xzf "$tmp/dl.tar.gz" -C "$tmp/x" --strip-components=1
    local src="$tmp/x"
    if [[ "$subdir" != "." && -n "$subdir" ]]; then
        src="$tmp/x/$subdir"
    fi
    if [[ ! -f "$src/manifest.json" ]]; then
        printf '%b\n' "  ${RED}[!] no manifest.json in ${name} (${subdir})${RESET}" >&2
        return 1
    fi
    rm -rf "${dir:?}/$name"
    mkdir -p "$dir/$name"
    cp -a "$src/." "$dir/$name/"
    echo "$tag" > "$dir/$name/.dotsec-version"
    printf '%b\n' "  ${GREEN}[+]${RESET} ${name} ${DIM}(${tag})${RESET}"
}

# __ext_fetch_webstore <name> <id> <version> <sha256>
# Downloads the pinned .crx, verifies sha256, carves out the zip payload
# (CRX2/CRX3 header skipped by locating the first PK\x03\x04), unzips into
# $DOTSEC_EXT_DIR/<name>/.
__ext_fetch_webstore() {
    local name="$1" id="$2" ver="$3" want="$4"
    local dir; dir="$(__ext_dir)"
    local url="https://clients2.google.com/service/update2/crx?response=redirect&acceptformat=crx2,crx3&prodversion=${ver}&x=id%3D${id}%26installsource%3Dondemand%26uc"
    local tmp; tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    if ! curl -fsSL "$url" -o "$tmp/e.crx"; then
        printf '%b\n' "  ${RED}[!] crx download failed: ${name}${RESET}" >&2
        return 1
    fi
    local got; got="$(sha256sum "$tmp/e.crx" | cut -d' ' -f1)"
    if [[ -n "$want" && "$got" != "$want" ]]; then
        printf '%b\n' "  ${RED}[!] sha256 mismatch for ${name}${RESET}" >&2
        printf '%b\n' "      want ${want}" >&2
        printf '%b\n' "      got  ${got}" >&2
        return 1
    fi
    # Skip the Cr24 header: the zip payload starts at the first PK\x03\x04.
    local off; off="$(grep -aboFm1 $'PK\x03\x04' "$tmp/e.crx" | cut -d: -f1 || true)"
    if [[ -z "$off" ]]; then
        printf '%b\n' "  ${RED}[!] no zip payload in crx ${name}${RESET}" >&2
        return 1
    fi
    tail -c "+$((off + 1))" "$tmp/e.crx" > "$tmp/e.zip"
    mkdir -p "$tmp/x"
    unzip -qo "$tmp/e.zip" -d "$tmp/x"
    if [[ ! -f "$tmp/x/manifest.json" ]]; then
        printf '%b\n' "  ${RED}[!] no manifest.json in crx ${name}${RESET}" >&2
        return 1
    fi
    rm -rf "${dir:?}/$name"
    mkdir -p "$dir/$name"
    cp -a "$tmp/x/." "$dir/$name/"
    echo "$ver" > "$dir/$name/.dotsec-version"
    printf '%b\n' "  ${GREEN}[+]${RESET} ${name} ${DIM}(crx ${ver})${RESET}"
}

# __ext_sync_one <name> <provider> <source> <ref> <sha256> <subdir>
__ext_sync_one() {
    local name="$1" provider="$2" src="$3" ref="$4" sha="$5" subdir="$6"
    if [[ -n "${__EXT_ONLY:-}" && "${__EXT_ONLY}" != "$name" ]]; then
        return 0
    fi
    local marker; marker="$(__ext_dir)/$name/.dotsec-version"
    if [[ -f "$marker" ]] && [[ "$(cat "$marker")" == "$ref" ]]; then
        printf '%b\n' "  ${DIM}= ${name} (up-to-date ${ref})${RESET}"
        return 0
    fi
    # One failing extension must not abort the whole sync; the error is printed.
    case "$provider" in
        github)   __ext_fetch_github   "$name" "$src" "$ref" "$sha" "$subdir" || true;;
        webstore) __ext_fetch_webstore "$name" "$src" "$ref" "$sha" || true;;
        *) printf '%b\n' "  ${RED}[!] unknown provider '${provider}' for ${name}${RESET}" >&2;;
    esac
}

# ext_sync [only]: install all (or one named) manifest entries into the ext dir.
ext_sync() {
    local only="${1:-}"
    local dir; dir="$(__ext_dir)"
    mkdir -p "$dir"
    printf '%b\n' "${YELLOW}[*]${RESET} Syncing extensions into ${CYAN}${dir}${RESET}"
    __EXT_ONLY="$only"
    __ext_each __ext_sync_one
    unset __EXT_ONLY
}

cmd_ext() {
    case "${1:-}" in
        list) shift; ext_list "$@";;
        sync) shift; ext_sync "$@";;
        *) printf '%b\n' "${RED}[!] dotsec ext sync|list${RESET}" >&2; return 1;;
    esac
}
