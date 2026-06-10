#!/usr/bin/env sh
set -e

echo "[*] Chromium proxy: ${HTTP_PROXY:-none set}"

if [ -n "$HTTP_PROXY" ]; then
    CHROMIUM_FLAGS="$CHROMIUM_FLAGS --proxy-server=$HTTP_PROXY"
fi

# Trust mitmproxy CA if mounted
CA_FILE=""
if [ -f /certs/mitmproxy-ca-cert.pem ]; then
    CA_FILE="/certs/mitmproxy-ca-cert.pem"
elif [ -f /certs/mitmproxy-ca.pem ]; then
    CA_FILE="/certs/mitmproxy-ca.pem"
fi

if [ -n "$CA_FILE" ]; then
    echo "[*] Importing mitmproxy CA..."

    # System trust store. Arch uses update-ca-trust + trust-source/anchors;
    # Debian uses update-ca-certificates + /usr/local/share/ca-certificates.
    # Best-effort only — Chromium trusts the CA via the NSS DB below, so a
    # missing system tool must never abort the launch (set -e).
    if command -v update-ca-trust >/dev/null 2>&1; then
        cp "$CA_FILE" /etc/ca-certificates/trust-source/anchors/mitmproxy-ca.crt 2>/dev/null \
            && update-ca-trust extract 2>/dev/null || true
    elif command -v update-ca-certificates >/dev/null 2>&1; then
        mkdir -p /usr/local/share/ca-certificates
        cp "$CA_FILE" /usr/local/share/ca-certificates/mitmproxy-ca.crt 2>/dev/null \
            && update-ca-certificates 2>/dev/null || true
    fi

    # Chromium NSS trust store (what Chromium actually reads). The DB is
    # pre-created in the image; only init it when missing. Always feed stdin
    # from /dev/null: on an existing DB certutil otherwise loops forever
    # prompting for the store password on a non-TTY.
    NSSDB="/root/.pki/nssdb"
    mkdir -p "$NSSDB"
    [ -f "$NSSDB/cert9.db" ] || certutil -N -d sql:"$NSSDB" --empty-password </dev/null 2>/dev/null || true
    certutil -A -d sql:"$NSSDB" -t "C,," -n "mitmproxy-proxy" \
        -i "$CA_FILE" </dev/null 2>/dev/null && \
        echo "[+] CA trusted (Chromium NSS)" || \
        echo "[!] CA trust failed : add --ignore-certificate-errors manually"
fi

# If proxy is set and no CA, warn
if [ -n "$HTTP_PROXY" ] && [ -z "$CA_FILE" ]; then
    CHROMIUM_FLAGS="$CHROMIUM_FLAGS --ignore-certificate-errors"
    echo "[!] No CA cert mounted: ignoring cert errors"
fi

# Preload extensions if provided
if [ -d /extensions ] && [ "$(ls -A /extensions 2>/dev/null)" ]; then
    EXT_FLAGS=""
    for ext in /extensions/*/; do
        EXT_FLAGS="$EXT_FLAGS --load-extension=$ext"
    done
    CHROMIUM_FLAGS="$CHROMIUM_FLAGS $EXT_FLAGS"
    echo "[+] Extensions loaded"
fi

echo "[*] Launching Chromium..."
# Arch's binary is `chromium` (not Debian's `chromium-browser`).
exec chromium $CHROMIUM_FLAGS ${1:-about:blank}
