#!/usr/bin/env sh
set -e

echo "[*] Chromium proxy: ${HTTP_PROXY:-none set}"

if [ -n "$HTTP_PROXY" ]; then
    CHROMIUM_FLAGS="$CHROMIUM_FLAGS --proxy-server=$HTTP_PROXY"
fi

# Trust mitmproxy CA if mounted
if [ -f /certs/mitmproxy-ca.pem ]; then
    echo "[*] Importing mitmproxy CA..."

    # System trust store
    cp /certs/mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy-ca.crt
    update-ca-certificates

    # Chromium NSS trust store
    NSSDB="/root/.pki/nssdb"
    mkdir -p "$NSSDB"
    certutil -N -d sql:"$NSSDB" --empty-password 2>/dev/null || true
    certutil -A -d sql:"$NSSDB" -t "C,," -n "mitmproxy-proxy" \
        -i /certs/mitmproxy-ca.pem 2>/dev/null && \
        echo "[+] CA trusted (system + Chromium NSS)" || \
        echo "[!] CA trust failed: add --ignore-certificate-errors manually"
fi

# If proxy is set and no CA, warn
if [ -n "$HTTP_PROXY" ] && [ ! -f /certs/mitmproxy-ca.pem ]; then
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
exec chromium-browser $CHROMIUM_FLAGS ${1:-about:blank}
