#!/bin/sh
set -euo pipefail

ROOT_DIR=/opt/soreal
DATA_DIR="${ROOT_DIR}/data"

mkdir -p "${DATA_DIR}"
chown -R docker:docker "${DATA_DIR}"

HOST_LC=$(printf '%s' "${HOST}" | tr 'A-Z' 'a-z')
if [ "${SELF_SIGN:-false}" = "true" ]; then
    CERT_FILE="${DATA_DIR}/caddy/data/certificates/local/${HOST_LC}/${HOST_LC}.crt"
    KEY_FILE="${DATA_DIR}/caddy/data/certificates/local/${HOST_LC}/${HOST_LC}.key"
else
    CERT_FILE="${DATA_DIR}/caddy/data/certificates/acme-v02.api.letsencrypt.org-directory/${HOST_LC}/${HOST_LC}.crt"
    KEY_FILE="${DATA_DIR}/caddy/data/certificates/acme-v02.api.letsencrypt.org-directory/${HOST_LC}/${HOST_LC}.key"
fi
export CERT_FILE KEY_FILE

su-exec docker python3 "${ROOT_DIR}/init.py"

(
    set +e
    su-exec docker env \
        XDG_CONFIG_HOME="${DATA_DIR}/caddy/config" \
        XDG_DATA_HOME="${DATA_DIR}/caddy/data" \
        HOME="${DATA_DIR}/caddy/home" \
        /usr/bin/caddy run --config "${ROOT_DIR}/caddyfile" --adapter caddyfile
    status=$?
    echo "Caddy exited with status ${status}..." >&2
    kill -TERM "$$"
) &

# certmagic writes the key and the cert as separate files; wait for both.
if [ ! -f "${CERT_FILE}" ] || [ ! -f "${KEY_FILE}" ]; then
    echo "Waiting for certificate at \"${CERT_FILE}\"..."
    until [ -f "${CERT_FILE}" ] && [ -f "${KEY_FILE}" ]; do sleep 1; done
fi
echo "Starting Xray..."

exec su-exec docker "${ROOT_DIR}/xray/xray" run -c "${ROOT_DIR}/xray.json"
