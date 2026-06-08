#!/usr/bin/env sh
set -e

echo "[*] Starting mitmweb: proxy:0.0.0.0:8080 | web:0.0.0.0:8081"
exec mitmweb \
    --set confdir=/data/certs \
    --mode regular@8080 \
    --web-host 0.0.0.0 \
    --web-port 8081 \
    --set save_stream_file=/data/flows/all.flow \
    --set stream_large_bodies=10m
