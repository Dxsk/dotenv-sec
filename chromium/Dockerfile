FROM archlinux:multilib-devel-20260609.0.542364@sha256:c18b3bf5eec167df12b270a28ad362b1b4463082da096d01aac5207edaf12003

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
