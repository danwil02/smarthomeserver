#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

export COMPOSE_PROJECT_NAME=smarthomeserver

echo "==> Stopping systemd services"
sudo systemctl stop reset-indexer-status.timer reset-indexer-status.service 2>/dev/null || true
echo "    reset-indexer-status.timer stopped"

echo "==> [1/6] Stopping apps stack"
docker compose --env-file .env.local -f docker-compose.apps.yml down

echo "==> [2/6] Stopping media stack"
docker compose --env-file .env.local -f docker-compose.media.yml down

echo "==> [3/6] Stopping home stack"
docker compose --env-file .env.local -f docker-compose.home.yml down

echo "==> [4/6] Stopping monitoring stack"
docker compose --env-file .env.local -f docker-compose.monitoring.yml down

echo "==> [5/6] Stopping auth stack"
docker compose --env-file .env.local -f docker-compose.auth.yml down

echo "==> [6/6] Stopping infra stack"
docker compose --env-file .env.local -f docker-compose.infra.yml down

echo "==> All stacks stopped (homelab network preserved)"
