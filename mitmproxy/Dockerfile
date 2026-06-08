FROM archlinux:multilib-devel-20260607.0.541780@sha256:e6c4eacdc7d29cf643f18e4cfb7a31a2e893a58812fb848ba082f8998e7ea79d

# mitmproxy + runtime deps (glibc = pre-built wheels, no compilation needed)
RUN pacman -Syu --noconfirm python python-pip python-cryptography && \
    pip install --break-system-packages --no-cache-dir mitmproxy && \
    pacman -Scc --noconfirm && rm -rf /var/cache/pacman/pkg/*

RUN useradd -m -s /bin/sh mitmproxy && \
    mkdir -p /data/flows /data/certs && \
    chown -R mitmproxy:mitmproxy /data

ENV HOME=/home/mitmproxy

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080 8081

VOLUME ["/data/flows", "/data/certs"]

ENTRYPOINT ["/entrypoint.sh"]
