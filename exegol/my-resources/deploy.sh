#!/usr/bin/env bash
# Deploy the dotsec recon bundle into the Exegol my-resources volume, merging
# delimited blocks idempotently (never clobbering the user's own customizations).
set -euo pipefail

DOTSEC_HOME="${DOTSEC_HOME:-$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)}"
SRC="${DOTSEC_HOME}/exegol/my-resources"
DEST="${MYRES_DIR:-${HOME}/.exegol/my-resources}"
BEGIN="# >>> dotsec >>>"
END="# <<< dotsec <<<"

# merge_block <dest_file> <fragment_file>: replace existing dotsec block or append.
merge_block() {
    local target="$1" fragment="$2"
    [[ -f "$fragment" ]] || return 0
    mkdir -p "$(dirname "$target")"
    touch "$target"
    if grep -qF "$BEGIN" "$target"; then
        sed -i "\|${BEGIN}|,\|${END}|d" "$target"
    fi
    { printf '%s\n' "$BEGIN"; cat "$fragment"; printf '%s\n' "$END"; } >> "$target"
}

mkdir -p "${DEST}/bin"
for prefix in recon- scan- audit-; do
    if compgen -G "${SRC}/bin/${prefix}*" >/dev/null; then
        cp "${SRC}/bin/${prefix}"* "${DEST}/bin/"
    fi
done
[[ -f "${SRC}/bin/dl" ]] && cp "${SRC}/bin/dl" "${DEST}/bin/"
chmod +x "${DEST}/bin/"* 2>/dev/null || true

merge_block "${DEST}/setup/zsh/aliases"          "${SRC}/fragments/aliases.dotsec"
merge_block "${DEST}/setup/zsh/history"          "${SRC}/fragments/history.dotsec"
merge_block "${DEST}/setup/load_user_setup.sh"   "${SRC}/fragments/load_user_setup.dotsec.sh"

printf '[+] dotsec recon toolkit deployed to %s\n' "${DEST}"
