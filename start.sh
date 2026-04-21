#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

export COMPOSE_PROJECT_NAME=smarthomeserver

NETWORK=homelab
LOKI_READY_URL="http://localhost:3100/ready"
LOKI_TIMEOUT=60

compose() {
  docker compose --env-file .env.local "$@" 2>&1 | grep -v "Found orphan containers"
}

echo "==> Ensuring '${NETWORK}' docker network exists"
if ! docker network inspect "${NETWORK}" >/dev/null 2>&1; then
  docker network create "${NETWORK}"
  echo "    created"
else
  echo "    already present"
fi

echo "==> [1/5] Starting infra stack"
compose -f docker-compose.infra.yml up -d

echo "==> [2/5] Starting monitoring stack"
compose -f docker-compose.monitoring.yml up -d

echo "==> Waiting up to ${LOKI_TIMEOUT}s for Loki to be ready"
elapsed=0
until curl -sf "${LOKI_READY_URL}" >/dev/null 2>&1; do
  if [ "${elapsed}" -ge "${LOKI_TIMEOUT}" ]; then
    echo "    ERROR: Loki did not become ready within ${LOKI_TIMEOUT}s" >&2
    exit 1
  fi
  sleep 2
  elapsed=$((elapsed + 2))
done
echo "    Loki ready after ${elapsed}s"

echo "==> [3/5] Starting home stack"
compose -f docker-compose.home.yml up -d

echo "==> [4/5] Starting media stack"
compose -f docker-compose.media.yml up -d

echo "==> [5/5] Starting apps stack"
compose -f docker-compose.apps.yml up -d

echo "==> All stacks started"
