FROM alpine:3.21@sha256:48b0309ca019d89d40f670aa1bc06e426dc0931948452e8491e3d65087abc07d

# Pinned deps: mitmproxy 11.0.2
RUN apk add --no-cache python3~=3.12 py3-pip~=24.3 py3-cryptography~=43.0 && \
    pip3 install --break-system-packages --no-cache-dir mitmproxy==11.0.2

# Non-root user for volume ownership (rootless Docker compat)
RUN adduser -D -h /home/mitmproxy -s /bin/sh mitmproxy && \
    mkdir -p /data/flows /data/certs && \
    chown -R mitmproxy:mitmproxy /data /home/mitmproxy

ENV HOME=/home/mitmproxy

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080 8081

VOLUME ["/data/flows", "/data/certs"]

ENTRYPOINT ["/entrypoint.sh"]
