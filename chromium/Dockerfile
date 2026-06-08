FROM alpine:3.21@sha256:48b0309ca019d89d40f670aa1bc06e426dc0931948452e8491e3d65087abc07d

# Pinned Chromium + runtime deps
RUN apk add --no-cache \
    chromium~=134 \
    chromium-chromedriver~=134 \
    nss~=3.107 \
    freetype~=2.13 \
    harfbuzz~=10.1 \
    ttf-freefont~=20120503 \
    dbus~=1.15 \
    xdg-utils~=1.2

# User + CA trust dir (rootless Docker compat)
RUN adduser -D -h /home/chromium -s /bin/sh chromium && \
    mkdir -p /home/chromium/.cache /home/chromium/.config /certs /extensions && \
    chown -R chromium:chromium /home/chromium /certs /extensions && \
    mkdir -p /usr/local/share/ca-certificates

ENV CHROMIUM_FLAGS="--no-sandbox --disable-gpu --disable-dev-shm-usage --disable-features=TranslateUI"
ENV HTTP_PROXY=""
ENV HTTPS_PROXY=""

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
