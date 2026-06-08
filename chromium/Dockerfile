FROM alpine:3.21

RUN apk add --no-cache \
    chromium \
    chromium-chromedriver \
    nss \
    freetype \
    harfbuzz \
    ttf-freefont \
    dbus \
    xdg-utils

# Trust mitmproxy CA
RUN mkdir -p /usr/local/share/ca-certificates

ENV CHROMIUM_FLAGS="--no-sandbox --disable-gpu --disable-dev-shm-usage"
ENV HTTP_PROXY=""
ENV HTTPS_PROXY=""

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
