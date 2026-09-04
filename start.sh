#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

MODE="start"
case "${1:-}" in
  --update)   MODE="update" ;;
  --rollback) MODE="rollback" ;;
  "")         MODE="start" ;;
  *)          echo "Usage: $0 [--update|--rollback]" >&2; exit 1 ;;
esac

PULL_FLAG=""
[ "${MODE}" = "update" ] && PULL_FLAG="--pull always"
[ "${MODE}" != "start" ] && echo "==> Mode: ${MODE} (PULL_FLAG='${PULL_FLAG}')"

export COMPOSE_PROJECT_NAME=smarthomeserver

NETWORK=homelab
LOKI_READY_URL="http://localhost:3100/ready"
LOKI_TIMEOUT=60

compose() {
  docker compose --env-file .env.local "$@" 2>&1 | grep -v "Found orphan containers"
}

# --update: snapshot each :latest image locally as :previous before the stack's
#   normal `up -d --pull always` fetches and recreates it.
# --rollback: retag :previous back onto :latest locally so the following plain
#   `up -d` recreates the container from the previous snapshot instead of pulling.
# Pinned images (no :latest tag) never match and are left untouched either way.
sync_latest_images() {
  local file="$1"
  [ "${MODE}" = "start" ] && return 0

  local pairs
  pairs=$(docker compose --env-file .env.local -f "$file" config --format json 2>/dev/null \
    | jq -r '.services | to_entries[] | select(.value.image != null and (.value.image | test(":latest$"))) | "\(.key)\t\(.value.image)"')
  [ -z "${pairs}" ] && return 0

  while IFS=$'\t' read -r service image; do
    local repo="${image%:latest}"
    if [ "${MODE}" = "update" ]; then
      if docker image inspect "${image}" >/dev/null 2>&1; then
        local old_id
        old_id=$(docker image inspect --format '{{.Id}}' "${image}" | cut -c8-19)
        docker tag "${image}" "${repo}:previous"
        echo "    [debug] snapshotted ${service}: ${old_id} -> ${repo}:previous"
      else
        echo "    [debug] ${service}: no local image yet, nothing to snapshot"
      fi
    elif [ "${MODE}" = "rollback" ]; then
      if docker image inspect "${repo}:previous" >/dev/null 2>&1; then
        local prev_id
        prev_id=$(docker image inspect --format '{{.Id}}' "${repo}:previous" | cut -c8-19)
        docker tag "${repo}:previous" "${image}"
        echo "    [debug] rolling back ${service} -> ${prev_id} (was tagged :previous)"
      else
        echo "    [debug] WARN: no previous snapshot for ${service}, skipping"
      fi
    fi
  done <<< "${pairs}"
}

# Post-up-d visibility: for every :latest service in the file, print the image ID
# actually backing the running container next to the local :latest and :previous
# tag IDs, so a validation run can confirm each stage landed in the expected state.
log_stack_state() {
  local file="$1"
  [ "${MODE}" = "start" ] && return 0

  local pairs
  pairs=$(docker compose --env-file .env.local -f "$file" config --format json 2>/dev/null \
    | jq -r '.services | to_entries[] | select(.value.image != null and (.value.image | test(":latest$"))) | "\(.key)\t\(.value.image)"')
  [ -z "${pairs}" ] && return 0

  printf "    [debug] %-16s %-14s %-14s %-14s\n" "SERVICE" "RUNNING" "LOCAL:latest" "LOCAL:previous"
  while IFS=$'\t' read -r service image; do
    local repo="${image%:latest}"
    local cid running_id latest_id previous_id
    cid=$(docker compose --env-file .env.local -f "$file" ps -q "${service}" 2>/dev/null || true)
    running_id="-"
    [ -n "${cid}" ] && running_id=$(docker inspect --format '{{.Image}}' "${cid}" 2>/dev/null | cut -c8-19)
    latest_id=$(docker image inspect --format '{{.Id}}' "${image}" 2>/dev/null | cut -c8-19)
    previous_id=$(docker image inspect --format '{{.Id}}' "${repo}:previous" 2>/dev/null | cut -c8-19)
    [ -z "${running_id}" ] && running_id="-"
    [ -z "${latest_id}" ] && latest_id="-"
    [ -z "${previous_id}" ] && previous_id="-"
    printf "    [debug] %-16s %-14s %-14s %-14s\n" "${service}" "${running_id}" "${latest_id}" "${previous_id}"
  done <<< "${pairs}"
}

echo "==> Ensuring '${NETWORK}' docker network exists"
if ! docker network inspect "${NETWORK}" >/dev/null 2>&1; then
  docker network create "${NETWORK}"
  echo "    created"
else
  echo "    already present"
fi

echo "==> [1/6] Starting infra stack"
sync_latest_images docker-compose.infra.yml
compose -f docker-compose.infra.yml up -d ${PULL_FLAG}
log_stack_state docker-compose.infra.yml

echo "==> [2/6] Starting auth stack"
sync_latest_images docker-compose.auth.yml
compose -f docker-compose.auth.yml up -d ${PULL_FLAG}
log_stack_state docker-compose.auth.yml

echo "==> Waiting up to 60s for Authelia to be healthy"
AUTHELIA_TIMEOUT=60
elapsed=0
until [ "$(docker inspect -f '{{.State.Health.Status}}' authelia 2>/dev/null)" = "healthy" ]; do
  if [ "${elapsed}" -ge "${AUTHELIA_TIMEOUT}" ]; then
    echo "    WARN: Authelia did not become healthy within ${AUTHELIA_TIMEOUT}s — SSO-gated services may 502 until it's ready" >&2
    break
  fi
  sleep 2
  elapsed=$((elapsed + 2))
done
[ "$(docker inspect -f '{{.State.Health.Status}}' authelia 2>/dev/null)" = "healthy" ] && echo "    Authelia healthy after ${elapsed}s"

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

echo "==> [3/6] Starting monitoring stack"
sync_latest_images docker-compose.monitoring.yml
compose -f docker-compose.monitoring.yml up -d ${PULL_FLAG}
log_stack_state docker-compose.monitoring.yml

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

echo "==> [4/6] Starting home stack"
sync_latest_images docker-compose.home.yml
compose -f docker-compose.home.yml up -d ${PULL_FLAG}
log_stack_state docker-compose.home.yml

echo "==> [5/6] Starting media stack"
sync_latest_images docker-compose.media.yml
compose -f docker-compose.media.yml up -d ${PULL_FLAG}
log_stack_state docker-compose.media.yml

echo "==> [6/6] Starting apps stack"
sync_latest_images docker-compose.apps.yml
compose -f docker-compose.apps.yml up -d ${PULL_FLAG}
log_stack_state docker-compose.apps.yml

echo "==> Installing systemd services"
SERVICES_DIR="$(pwd)/services"
SYSTEMD_DIR="/etc/systemd/system"
RELOAD_NEEDED=false
CHANGED_UNITS=()

# Install any changed or missing unit files
for src in "${SERVICES_DIR}"/*.service "${SERVICES_DIR}"/*.timer; do
  [ -f "${src}" ] || continue
  unit="$(basename "${src}")"
  dst="${SYSTEMD_DIR}/${unit}"
  if [ ! -f "${dst}" ] || ! diff -q "${src}" "${dst}" >/dev/null 2>&1; then
    sudo cp "${src}" "${dst}"
    echo "    installed: ${unit}"
    RELOAD_NEEDED=true
    CHANGED_UNITS+=("${unit}")
  else
    echo "    unchanged: ${unit}"
  fi
done

${RELOAD_NEEDED} && sudo systemctl daemon-reload

# Enable timers; enable services that have no paired timer
for src in "${SERVICES_DIR}"/*.timer "${SERVICES_DIR}"/*.service; do
  [ -f "${src}" ] || continue
  unit="$(basename "${src}")"
  base="${unit%.*}"
  ext="${unit##*.}"

  # Skip services that are driven by a timer
  if [ "${ext}" = "service" ] && [ -f "${SERVICES_DIR}/${base}.timer" ]; then
    continue
  fi

  changed=false
  for u in "${CHANGED_UNITS[@]+"${CHANGED_UNITS[@]}"}"; do
    [ "${u}" = "${unit}" ] && changed=true && break
  done

  if ! systemctl is-enabled --quiet "${unit}" 2>/dev/null; then
    sudo systemctl enable --now "${unit}"
    echo "    enabled and started: ${unit}"
  elif ${changed}; then
    sudo systemctl restart "${unit}"
    echo "    restarted (unit changed): ${unit}"
  else
    echo "    already enabled, no changes: ${unit}"
  fi
done

case "${MODE}" in
  update)   echo "==> All stacks started (:latest images updated; previous versions tagged :previous for rollback)" ;;
  rollback) echo "==> All stacks started (:latest images rolled back to previous snapshot)" ;;
  *)        echo "==> All stacks started" ;;
esac
