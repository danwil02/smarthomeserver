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

echo "==> Checking Tailscale DNS setup"
if ! command -v tailscale >/dev/null 2>&1; then
  echo "    tailscale CLI not found — skipping DNS check"
elif ! command -v dig >/dev/null 2>&1; then
  echo "    dig not found — skipping DNS check (install dnsutils to enable)"
else
  TS_IP=$(tailscale ip -4 2>/dev/null || echo "")
  if [ -z "${TS_IP}" ]; then
    echo "    tailscale not connected — skipping DNS check"
  else
    # Give dnsmasq a moment to start
    sleep 2

    # Check dnsmasq is answering *.lab queries correctly
    RESOLVED=$(dig +short +time=2 "probe.lab" "@${TS_IP}" 2>/dev/null | head -1)
    if [ "${RESOLVED}" = "${TS_IP}" ]; then
      echo "    dnsmasq: answering *.lab → ${TS_IP} ✓"
    else
      echo "    WARN: dnsmasq not answering correctly (got '${RESOLVED}', expected '${TS_IP}')"
    fi

    # Check if Tailscale split DNS is active (*.lab resolves without specifying nameserver)
    TS_RESOLVED=$(dig +short +time=2 "probe.lab" 2>/dev/null | head -1)
    if [ "${TS_RESOLVED}" = "${TS_IP}" ]; then
      echo "    Tailscale split DNS: active ✓"
    else
      echo "    Tailscale split DNS: NOT configured"
      echo ""
      echo "    One-time setup required in Tailscale admin:"
      echo "    https://login.tailscale.com/admin/dns"
      echo "    → Add nameserver: ${TS_IP}"
      echo "    → Restrict to domain: lab"
      echo ""
    fi
  fi
fi

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

echo "==> Installing systemd services"
SERVICES_DIR="$(pwd)/services"
sudo cp "${SERVICES_DIR}/reset-indexer-status.service" /etc/systemd/system/
sudo cp "${SERVICES_DIR}/reset-indexer-status.timer"   /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now reset-indexer-status.timer
echo "    reset-indexer-status.timer enabled and started"

echo "==> All stacks started"
