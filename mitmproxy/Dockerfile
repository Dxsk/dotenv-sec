FROM alpine:3.21

RUN apk add --no-cache python3 py3-pip py3-cryptography && \
    pip3 install --break-system-packages mitmproxy==11.0.2

RUN mkdir -p /home/mitmproxy/.mitmproxy /data/flows /data/certs
ENV HOME=/home/mitmproxy

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080 8081

VOLUME ["/data/flows", "/data/certs"]

ENTRYPOINT ["/entrypoint.sh"]
