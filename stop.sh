#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

export COMPOSE_PROJECT_NAME=smarthomeserver

echo "==> [1/5] Stopping apps stack"
docker compose --env-file .env.local -f docker-compose.apps.yml down

echo "==> [2/5] Stopping media stack"
docker compose --env-file .env.local -f docker-compose.media.yml down

echo "==> [3/5] Stopping home stack"
docker compose --env-file .env.local -f docker-compose.home.yml down

echo "==> [4/5] Stopping monitoring stack"
docker compose --env-file .env.local -f docker-compose.monitoring.yml down

echo "==> [5/5] Stopping infra stack"
docker compose --env-file .env.local -f docker-compose.infra.yml down

echo "==> All stacks stopped (homelab network preserved)"
