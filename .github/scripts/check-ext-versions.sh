#!/usr/bin/env bash
# ─── check-ext-versions.sh ───────────────────────────────────────────────────
# Vérifie que chaque extension épinglée dans chromium/extensions.list pointe sur
# la dernière version publiée en amont. Appelé par le scheduleur hebdo
# (.github/workflows/scheduled-scan.yml).
#
#   provider github   : compare le tag épinglé à la dernière release/tag GitHub.
#   provider webstore : compare la version épinglée à l'endpoint updatecheck Google.
#
# Sortie :
#   0  toutes les extensions sont à jour
#   1  au moins une extension est en retard (une version plus récente existe)
#   2  uniquement si EXT_STRICT=1 et qu'au moins un fetch a échoué sans retard détecté
#
# Variables d'environnement :
#   EXT_MANIFEST       chemin du manifest        (défaut: <repo>/chromium/extensions.list)
#   EXT_OUTDATED_FILE  écrit les retards en Markdown (pour le corps d'issue CI)
#   EXT_STRICT         1 → un fetch échoué fait sortir en 2 (défaut: lenient, warning)
#   GITHUB_TOKEN       authentifie l'API GitHub pour éviter le rate-limit
#   DOTSEC_CHROME_MAJOR  prodversion envoyée au Web Store (défaut: 149)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="${EXT_MANIFEST:-${ROOT}/chromium/extensions.list}"
CHROME_MAJOR="${DOTSEC_CHROME_MAJOR:-149}"

if [[ -t 1 && "${TERM:-dumb}" != "dumb" ]]; then
    RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; DIM=''; RESET=''
fi

__trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# Récupère une URL ; ajoute l'auth GitHub si pertinent. Échoue (≠0) sur erreur HTTP.
__http() {
    local url="$1"
    if [[ "$url" == *api.github.com* && -n "${GITHUB_TOKEN:-}" ]]; then
        curl -fsSL \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer ${GITHUB_TOKEN}" \
            "$url"
    else
        curl -fsSL "$url"
    fi
}

# Dernière version github : release/latest puis fallback sur le premier tag.
__latest_github() {
    local repo="$1" body tag
    # 404 attendu pour les repos sans release → on bascule sur /tags, donc on tait stderr ici.
    if body="$(__http "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null)"; then
        tag="$(printf '%s' "$body" | grep -oP '"tag_name"\s*:\s*"\K[^"]+' | head -1 || true)"
        [[ -n "$tag" ]] && { printf '%s' "$tag"; return 0; }
    fi
    body="$(__http "https://api.github.com/repos/${repo}/tags")" || return 1
    tag="$(printf '%s' "$body" | grep -oP '"name"\s*:\s*"\K[^"]+' | head -1 || true)"
    [[ -n "$tag" ]] || return 1
    printf '%s' "$tag"
}

# Dernière version Web Store via l'endpoint updatecheck (XML : version="x.y.z").
__latest_webstore() {
    local id="$1" body ver
    local url="https://clients2.google.com/service/update2/crx?response=updatecheck&prodversion=${CHROME_MAJOR}&x=id%3D${id}%26installsource%3Dondemand%26uc"
    body="$(__http "$url")" || return 1
    ver="$(printf '%s' "$body" | grep -oP 'version="\K[^"]+' | head -1 || true)"
    [[ -n "$ver" ]] || return 1
    printf '%s' "$ver"
}

# Vrai (0) si $2 est strictement plus récent que $1 (préfixe « v » ignoré).
__is_newer() {
    local cur="${1#v}" latest="${2#v}" top
    [[ "$cur" == "$latest" ]] && return 1
    top="$(printf '%s\n%s\n' "$cur" "$latest" | sort -V | tail -1)"
    [[ "$top" == "$latest" && "$top" != "$cur" ]]
}

if [[ ! -f "$MANIFEST" ]]; then
    printf '%b\n' "${RED}[!] manifest introuvable: ${MANIFEST}${RESET}" >&2
    exit 2
fi

printf '%b\n' "${DIM}Manifest: ${MANIFEST}${RESET}"

n_ok=0; n_outdated=0; n_error=0
outdated_report=""

while IFS='|' read -r name provider src ref _sha _subdir; do
    name="$(__trim "${name:-}")"
    [[ -z "$name" || "$name" == \#* ]] && continue
    provider="$(__trim "${provider:-}")"
    src="$(__trim "${src:-}")"
    ref="$(__trim "${ref:-}")"

    case "$provider" in
        github)   latest="$(__latest_github   "$src")" || latest="";;
        webstore) latest="$(__latest_webstore "$src")" || latest="";;
        *) printf '%b\n' "  ${RED}[!]${RESET} ${name} ${DIM}(provider inconnu '${provider}')${RESET}" >&2
           n_error=$((n_error + 1)); continue;;
    esac

    if [[ -z "$latest" ]]; then
        printf '%b\n' "  ${YELLOW}[?]${RESET} ${name} ${DIM}(version amont indéterminée)${RESET}" >&2
        n_error=$((n_error + 1))
        continue
    fi

    if __is_newer "$ref" "$latest"; then
        printf '%b\n' "  ${RED}[!] ${name}${RESET} ${ref} ${RED}→ ${latest}${RESET} ${DIM}(${provider})${RESET}"
        n_outdated=$((n_outdated + 1))
        outdated_report+="- **${name}** (${provider}): \`${ref}\` → \`${latest}\`"$'\n'
    else
        printf '%b\n' "  ${GREEN}[=]${RESET} ${name} ${DIM}(${ref}, à jour)${RESET}"
        n_ok=$((n_ok + 1))
    fi
done < "$MANIFEST"

printf '%b\n' "${DIM}---${RESET}"
printf '%b\n' "à jour: ${GREEN}${n_ok}${RESET}  en retard: ${RED}${n_outdated}${RESET}  erreurs: ${YELLOW}${n_error}${RESET}"

if [[ -n "${EXT_OUTDATED_FILE:-}" && -n "$outdated_report" ]]; then
    printf '%s' "$outdated_report" > "$EXT_OUTDATED_FILE"
fi

if (( n_outdated > 0 )); then
    exit 1
fi
if (( n_error > 0 )) && [[ "${EXT_STRICT:-0}" == "1" ]]; then
    exit 2
fi
exit 0
