#!/usr/bin/env bash
# ─── lib/secrets.sh ─── per-engagement secret generation ──
# Sourced by bin/dotsec. Depends on ui.sh for colors.
# Lib functions are PURE (no prompts); confirmations live in bin/dotsec.

# Random alnum string, pipefail-safe (head closes the pipe → SIGPIPE on tr).
__sec_rand() {
    local len="${1:-32}"
    ( set +o pipefail; tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$len" )
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
    [[ -f "${keydir}/id_ed25519.pub" ]] && chmod 644 "${keydir}/id_ed25519.pub"
    return 0
}
