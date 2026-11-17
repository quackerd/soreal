FROM alpine:latest

ARG ROOT_DIR="/opt/soreal"

RUN apk add --no-cache python3 py3-jinja2 libqrencode-tools ca-certificates su-exec caddy

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
mkdir -p "${ROOT_DIR}/xray"
curl -fsSL "${DOWNLOAD_URL}" -o /tmp/xray.zip
unzip -o /tmp/xray.zip -d "${ROOT_DIR}/xray/"
chmod +x "${ROOT_DIR}/xray/xray"
echo "Xray: $DOWNLOAD_URL"

chown -R docker:docker "${ROOT_DIR}/xray"

apk del .build-deps
EOF

#
# Configs
#
COPY --chown=docker:docker ./opt "${ROOT_DIR}/"

RUN chmod +x "${ROOT_DIR}/entrypoint.sh"

EXPOSE 80
VOLUME ${ROOT_DIR}/data
ENTRYPOINT ["/opt/soreal/entrypoint.sh"]
