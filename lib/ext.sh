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

ext_sync() {
    # Orchestration implemented in a later task.
    printf '%b\n' "${YELLOW}[*]${RESET} ${DIM}ext sync not yet implemented${RESET}" >&2
    return 0
}

cmd_ext() {
    case "${1:-}" in
        list) shift; ext_list "$@";;
        sync) shift; ext_sync "$@";;
        *) printf '%b\n' "${RED}[!] dotsec ext sync|list${RESET}" >&2; return 1;;
    esac
}
