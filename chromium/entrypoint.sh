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

    # System trust store
    cp "$CA_FILE" /usr/local/share/ca-certificates/mitmproxy-ca.crt
    update-ca-certificates

    # Chromium NSS trust store
    NSSDB="/root/.pki/nssdb"
    mkdir -p "$NSSDB"
    certutil -N -d sql:"$NSSDB" --empty-password 2>/dev/null || true
    certutil -A -d sql:"$NSSDB" -t "C,," -n "mitmproxy-proxy" \
        -i "$CA_FILE" 2>/dev/null && \
        echo "[+] CA trusted (system + Chromium NSS)" || \
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
