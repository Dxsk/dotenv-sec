#!/usr/bin/env sh
set -e

WEB_USER="${WEB_USER:-admin}"

# Use WEB_PASS from env, or generate + persist one
if [ -z "$WEB_PASS" ]; then
    PASS_FILE="/data/certs/.web-pass"
    if [ -f "$PASS_FILE" ]; then
        WEB_PASS=$(cat "$PASS_FILE")
    else
        WEB_PASS=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)
        echo "$WEB_PASS" > "$PASS_FILE"
    fi
fi

echo "[*] mitmweb: http://0.0.0.0:8081  password=${WEB_PASS}"
echo "[*] proxy  : http://0.0.0.0:8080"

exec mitmweb \
    --set confdir=/data/certs \
    --mode regular@8080 \
    --web-host 0.0.0.0 \
    --web-port 8081 \
    --set web_password="${WEB_PASS}" \
    --set save_stream_file=/data/flows/all.flow \
    --set stream_large_bodies=10m
