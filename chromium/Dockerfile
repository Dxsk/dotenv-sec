FROM archlinux:multilib-devel@sha256:e6c4eacdc7d29cf643f18e4cfb7a31a2e893a58812fb848ba082f8998e7ea79d

# Chromium + NSS tools for CA trust
RUN pacman -Syu --noconfirm \
    chromium \
    nss \
    freetype2 \
    harfbuzz \
    ttf-freefont \
    dbus \
    xdg-utils && \
    pacman -Scc --noconfirm && rm -rf /var/cache/pacman/pkg/*

RUN useradd -m -s /bin/sh chromium && \
    mkdir -p /home/chromium/.cache /home/chromium/.config /certs /extensions && \
    chown -R chromium:chromium /home/chromium /certs /extensions && \
    # Pre-init NSS cert DB for mitmproxy CA
    mkdir -p /root/.pki/nssdb && \
    certutil -N -d sql:/root/.pki/nssdb --empty-password

ENV CHROMIUM_FLAGS="--no-sandbox --disable-gpu --disable-dev-shm-usage --disable-features=TranslateUI"
ENV HTTP_PROXY=""
ENV HTTPS_PROXY=""

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
