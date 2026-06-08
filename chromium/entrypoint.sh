#!/usr/bin/env sh
set -e

echo "[*] Chromium proxy: ${HTTP_PROXY:-none set}"

if [ -n "$HTTP_PROXY" ]; then
    CHROMIUM_FLAGS="$CHROMIUM_FLAGS --proxy-server=$HTTP_PROXY"
fi

# Trust mitmproxy CA if mounted
if [ -f /certs/mitmproxy-ca.pem ]; then
    cp /certs/mitmproxy-ca.pem /usr/local/share/ca-certificates/mitmproxy-ca.crt
    update-ca-certificates
    echo "[+] mitmproxy CA trusted"
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
