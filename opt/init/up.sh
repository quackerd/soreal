#!/bin/sh
set -eu

DATA_DIR=/opt/soreal/data
mkdir -p "${DATA_DIR}/xray"
chown -R docker:docker "${DATA_DIR}"

HOST_LC=$(printf '%s' "${HOST}" | tr 'A-Z' 'a-z')
if [ "${SELF_SIGN:-false}" = "true" ]; then
    CERT_FILE="${DATA_DIR}/caddy/certificates/local/${HOST_LC}/${HOST_LC}.crt"
    KEY_FILE="${DATA_DIR}/caddy/certificates/local/${HOST_LC}/${HOST_LC}.key"
else
    CERT_FILE="${DATA_DIR}/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${HOST_LC}/${HOST_LC}.crt"
    KEY_FILE="${DATA_DIR}/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${HOST_LC}/${HOST_LC}.key"
fi
export CERT_FILE KEY_FILE

s6-setuidgid docker python3 /opt/init/init.py

printf '%s' "${CERT_FILE}" > /var/run/s6/container_environment/CERT_FILE
printf '%s' "${KEY_FILE}" > /var/run/s6/container_environment/KEY_FILE
