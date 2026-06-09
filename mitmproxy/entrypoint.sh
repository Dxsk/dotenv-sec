#!/usr/bin/env sh
set -e

WEB_USER="${WEB_USER:-admin}"
WEB_PASS="${WEB_PASS:-}"
PASS_FILE="/data/certs/.web-pass"

# Generate password if not provided
if [ -z "$WEB_PASS" ]; then
    if [ -f "$PASS_FILE" ]; then
        WEB_PASS=$(cat "$PASS_FILE")
    else
        WEB_PASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)
        echo "$WEB_PASS" > "$PASS_FILE"
    fi
fi

echo "[*] mitmweb: http://0.0.0.0:8081  user=${WEB_USER}  pass=${WEB_PASS}"
echo "[*] proxy  : http://0.0.0.0:8080"

exec mitmweb \
    --set confdir=/data/certs \
    --mode regular@8080 \
    --web-host 0.0.0.0 \
    --web-port 8081 \
    --set web_auth="${WEB_USER}:${WEB_PASS}" \
    --set save_stream_file=/data/flows/all.flow \
    --set stream_large_bodies=10m
