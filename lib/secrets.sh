#!/usr/bin/env bash
# ─── lib/secrets.sh ─── per-engagement secret generation ──
# Sourced by bin/dotsec. Depends on ui.sh for colors.
# Lib functions are PURE (no prompts); confirmations live in bin/dotsec.

# Random alnum string of EXACTLY $len chars.
# - LC_ALL=C: tr treats /dev/urandom byte-by-byte (a UTF-8 locale lets multibyte
#   sequences through, yielding non-ASCII / short output).
# - loop + trim: on some runners `tr | head` returns short (SIGPIPE/coreutils
#   pipe behaviour), so accumulate until we have enough, then slice to $len.
# - set +o pipefail inside the subshell: head closing the pipe SIGPIPEs tr.
__sec_rand() {
    local len="${1:-32}" out="" tries=0
    while (( ${#out} < len )) && (( tries < 64 )); do
        out+="$( set +o pipefail; LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c "$len" )"
        tries=$(( tries + 1 ))
    done
    printf '%s' "${out:0:len}"
}

# Upsert `export KEY="VALUE"` in an env file (idempotent).
__sec_env_set() {
    local file="$1" key="$2" value="$3"
    touch "$file"
    if grep -qE "^(export[[:space:]]+)?${key}=" "$file" 2>/dev/null; then
        sed -i -E "s|^(export[[:space:]]+)?${key}=.*|export ${key}=\"${value}\"|" "$file"
    else
        echo "export ${key}=\"${value}\"" >> "$file"
    fi
}

# Refuse env files containing command substitution.
__sec_guard_envfile() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    if grep -qE '^[[:space:]]*(export[[:space:]]+)?[a-zA-Z_][a-zA-Z0-9_]*=.*(\$\(|`)' "$file"; then
        return 1
    fi
    return 0
}

# 600 for files, 700 for dirs.
__sec_chmod_strict() {
    local path
    for path in "$@"; do
        [[ -e "$path" ]] || continue
        if [[ -d "$path" ]]; then chmod 700 "$path"; else chmod 600 "$path"; fi
    done
}

# Generate every MISSING secret for a workspace. Idempotent.
secrets_init() {
    local ws="$1"
    local secfile="${ws}/.env.secrets"
    local keydir="${ws}/keys"
    mkdir -p "$ws" "$keydir" "${ws}/proxy/certs"

    grep -qE '^(export[[:space:]]+)?DOTSEC_SESSION_SECRET=' "$secfile" 2>/dev/null \
        || __sec_env_set "$secfile" DOTSEC_SESSION_SECRET "$(__sec_rand 32)"
    grep -qE '^(export[[:space:]]+)?DOTSEC_API_TOKEN=' "$secfile" 2>/dev/null \
        || __sec_env_set "$secfile" DOTSEC_API_TOKEN "$(__sec_rand 32)"
    grep -qE '^(export[[:space:]]+)?MITMWEB_PASS=' "$secfile" 2>/dev/null \
        || __sec_env_set "$secfile" MITMWEB_PASS "$(__sec_rand 16)"

    if [[ ! -f "${keydir}/id_ed25519" ]]; then
        ssh-keygen -t ed25519 -N "" -C "dotsec-$(basename "$ws")" \
            -f "${keydir}/id_ed25519" >/dev/null 2>&1
    fi

    __sec_chmod_strict "$secfile" "$keydir" "${keydir}/id_ed25519"
    if [[ -f "${keydir}/id_ed25519.pub" ]]; then chmod 644 "${keydir}/id_ed25519.pub"; fi
    return 0
}

__sec_rot_token() {
    local f="$1/.env.secrets"
    __sec_env_set "$f" DOTSEC_SESSION_SECRET "$(__sec_rand 32)"
    __sec_env_set "$f" DOTSEC_API_TOKEN "$(__sec_rand 32)"
    __sec_chmod_strict "$f"
}
__sec_rot_mitmweb() {
    local f="$1/.env.secrets"
    __sec_env_set "$f" MITMWEB_PASS "$(__sec_rand 16)"
    __sec_chmod_strict "$f"
}
__sec_rot_ssh() {
    local d="$1/keys"
    mkdir -p "$d"
    rm -f "$d/id_ed25519" "$d/id_ed25519.pub"
    ssh-keygen -t ed25519 -N "" -C "dotsec-$(basename "$1")" -f "$d/id_ed25519" >/dev/null 2>&1
    __sec_chmod_strict "$d" "$d/id_ed25519"
    if [[ -f "$d/id_ed25519.pub" ]]; then chmod 644 "$d/id_ed25519.pub"; fi
}
__sec_rot_ca() {
    rm -f "$1"/proxy/certs/mitmproxy-ca* 2>/dev/null || true
}

# Force regeneration. type ∈ all|token|mitmweb|ssh|ca. PURE (no prompt).
secrets_rotate() {
    local ws="$1" type="${2:-all}"
    case "$type" in
        all)     __sec_rot_token "$ws"; __sec_rot_mitmweb "$ws"; __sec_rot_ssh "$ws"; __sec_rot_ca "$ws" ;;
        token)   __sec_rot_token "$ws" ;;
        mitmweb) __sec_rot_mitmweb "$ws" ;;
        ssh)     __sec_rot_ssh "$ws" ;;
        ca)      __sec_rot_ca "$ws" ;;
        *) printf '%b\n' "${RED}[!] Unknown secret type: ${type}${RESET} ${DIM}(all|token|mitmweb|ssh|ca)${RESET}" >&2; return 1 ;;
    esac
    return 0
}

# Masked summary: presence + SSH fingerprint + CA path. Never prints values.
secrets_show() {
    local ws="$1"
    local secfile="${ws}/.env.secrets"
    local keydir="${ws}/keys"
    local key
    printf '%b\n' "${BOLD}${CYAN}Secrets${RESET} ${DIM}${ws}${RESET}"
    for key in DOTSEC_SESSION_SECRET DOTSEC_API_TOKEN MITMWEB_PASS; do
        if grep -qE "^(export[[:space:]]+)?${key}=" "$secfile" 2>/dev/null; then
            printf '%b\n' "  ${GREEN}✓${RESET} ${key} ${DIM}(set)${RESET}"
        else
            printf '%b\n' "  ${RED}✗${RESET} ${key} ${DIM}(missing)${RESET}"
        fi
    done
    if [[ -f "${keydir}/id_ed25519.pub" ]]; then
        local fp
        fp=$(ssh-keygen -lf "${keydir}/id_ed25519.pub" 2>/dev/null | awk '{print $2}')
        printf '%b\n' "  ${GREEN}✓${RESET} SSH ${DIM}${fp}${RESET}"
    else
        printf '%b\n' "  ${RED}✗${RESET} SSH ${DIM}(missing)${RESET}"
    fi
    if ls "${ws}"/proxy/certs/mitmproxy-ca*.pem >/dev/null 2>&1; then
        printf '%b\n' "  ${GREEN}✓${RESET} CA  ${DIM}${ws}/proxy/certs${RESET}"
    else
        printf '%b\n' "  ${YELLOW}…${RESET} CA  ${DIM}(generated on proxy up)${RESET}"
    fi
}
