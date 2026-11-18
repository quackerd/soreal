FROM alpine:latest

ARG ROOT_DIR="/opt/soreal"

RUN apk add --no-cache python3 py3-jinja2 libqrencode-tools ca-certificates caddy s6-overlay

#
#  GID/UID, initial directory
#
RUN addgroup -g 1000 -S docker && \
    adduser -u 1000 -G docker -S docker && \
    mkdir -p "${ROOT_DIR}" && \
    chown docker:docker -R "${ROOT_DIR}"

#
# Xray
#
RUN <<EOF
set -euxo pipefail

apk add --no-cache --virtual .build-deps curl jq unzip

DOWNLOAD_URL=$(curl -fsSL https://api.github.com/repos/XTLS/Xray-core/releases/latest \
  | jq -r '.assets[] | select(.name == "Xray-linux-64.zip") | .browser_download_url')
mkdir -p /opt/xray
curl -fsSL "${DOWNLOAD_URL}" -o /tmp/xray.zip
unzip -o /tmp/xray.zip -d /opt/xray/
chmod +x /opt/xray/xray
echo "Xray: $DOWNLOAD_URL"

chown -R docker:docker /opt/xray

apk del .build-deps
EOF

COPY --chown=docker:docker ./opt /opt/

COPY --chmod=755 ./s6 /etc/s6-overlay/s6-rc.d/

EXPOSE 80
VOLUME ${ROOT_DIR}/data
ENTRYPOINT ["/init"]
