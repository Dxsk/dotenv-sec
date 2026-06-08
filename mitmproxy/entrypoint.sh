#!/usr/bin/env sh
set -e

# Generate CA cert if not present
if [ ! -f /data/certs/mitmproxy-ca.pem ]; then
    echo "[*] Generating CA certificate..."
    mitmdump --set confdir=/data/certs -q &
    MITM_PID=$!
    sleep 2
    kill $MITM_PID 2>/dev/null || true
    cp /data/certs/mitmproxy-ca-cert.pem /data/certs/mitmproxy-ca.pem 2>/dev/null || true
    echo "[+] CA cert ready at /data/certs/mitmproxy-ca.pem"
fi

echo "[*] Starting mitmweb on 0.0.0.0:8081 (proxy: 0.0.0.0:8080)"
exec mitmweb \
    --set confdir=/data/certs \
    --mode regular@8080 \
    --web-host 0.0.0.0 \
    --web-port 8081 \
    --set save_stream_file=/data/flows/flows
