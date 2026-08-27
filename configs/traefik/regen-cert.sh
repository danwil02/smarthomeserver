#!/usr/bin/env bash
# Reissues configs/traefik/certs/lab.crt with a SAN entry for every *.lab
# hostname currently referenced across the compose files + dynamic.yml.
# Run this whenever a new service gets a Traefik router, then restart traefik.
set -euo pipefail

cd "$(dirname "$0")/../.."   # repo root
CERT_DIR="configs/traefik/certs"

if [ ! -f "${CERT_DIR}/ca.key" ] || [ ! -f "${CERT_DIR}/ca.crt" ]; then
  echo "ERROR: ${CERT_DIR}/ca.key or ca.crt not found — the root CA must already exist." >&2
  exit 1
fi

HOSTS=$(grep -h 'Host(' docker-compose.*.yml configs/traefik/dynamic.yml \
  | grep -oE '[a-z0-9-]+\.lab' | sort -u)

COUNT=$(echo "${HOSTS}" | wc -l)
echo "==> Found ${COUNT} .lab hostnames:"
echo "${HOSTS}" | sed 's/^/    /'

SAN=$(echo "${HOSTS}" | sed 's/^/DNS:/' | paste -sd, -)

openssl genrsa -out "${CERT_DIR}/lab.key" 2048 2>/dev/null
openssl req -new -key "${CERT_DIR}/lab.key" -subj "/CN=smarthomeserver.lab" -out "${CERT_DIR}/lab.csr"
echo "subjectAltName = ${SAN}" > "${CERT_DIR}/lab.ext"

openssl x509 -req -in "${CERT_DIR}/lab.csr" -CA "${CERT_DIR}/ca.crt" -CAkey "${CERT_DIR}/ca.key" \
  -CAcreateserial -out "${CERT_DIR}/lab.crt" -days 825 -sha256 -extfile "${CERT_DIR}/lab.ext"

rm -f "${CERT_DIR}/lab.csr" "${CERT_DIR}/lab.ext"
chmod 600 "${CERT_DIR}/lab.key"

echo "==> Reissued ${CERT_DIR}/lab.crt (valid $(openssl x509 -in "${CERT_DIR}/lab.crt" -noout -enddate | cut -d= -f2))"
echo "==> Now run: docker compose --env-file .env.local -f docker-compose.infra.yml restart traefik"
