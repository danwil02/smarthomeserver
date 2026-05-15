#!/usr/bin/env bash
# Resets Prowlarr/Radarr/Sonarr/Lidarr indexer circuit breakers when the network
# is available but indexers are marked failed. Runs on a 5-minute timer so it
# clears within minutes of the network recovering, whether from a cold start or a
# sustained outage while containers were running.

set -euo pipefail

ENV_FILE="/home/will/smarthomeserver/.env.local"

get_env() {
    grep -E "^${1}=" "${ENV_FILE}" | cut -d= -f2- | tr -d '"' | head -1
}

PROWLARR_KEY=$(get_env PROWLARR_API_KEY)
RADARR_KEY=$(get_env RADARR_API_KEY)
SONARR_KEY=$(get_env SONARR_API_KEY)
LIDARR_KEY=$(get_env LIDARR_API_KEY)

CURL="curl -sf --max-time 5"

# Check if any of the API keys are set, otherwise there's no point in running
if [ -z "$PROWLARR_KEY" ] && [ -z "$RADARR_KEY" ] && [ -z "$SONARR_KEY" ] && [ -z "$LIDARR_KEY" ]; then
    # Print which api key is missing
    [ -z "$PROWLARR_KEY" ] && echo "Prowlarr API key is missing"
    [ -z "$RADARR_KEY" ] && echo "Radarr API key is missing"
    [ -z "$SONARR_KEY" ] && echo "Sonarr API key is missing"
    [ -z "$LIDARR_KEY" ] && echo "Lidarr API key is missing"
    exit 1
fi

# Bail if internet is not reachable
if ! $CURL https://1.1.1.1 > /dev/null 2>&1; then
    echo "Internet not reachable, skipping indexer status reset"
    exit 0
fi

reset_if_failed() {
    local name="$1" url="$2" key="$3" path="$4"
    [ -z "$key" ] && return 0
    local status
    status=$($CURL "${url}${path}" -H "X-Api-Key: ${key}" 2>/dev/null) || return 0
    # Non-empty array means there are failed indexers
    if [ -n "$status" ] && [ "$status" != "[]" ]; then
        $CURL -X DELETE "${url}${path}" -H "X-Api-Key: ${key}" > /dev/null || true
        logger -t reset-indexer-status "Reset failed indexers for ${name}"
    fi
}

reset_if_failed "Prowlarr" "http://localhost:9696" "$PROWLARR_KEY" "/api/v1/indexerstatus"
reset_if_failed "Radarr"   "http://localhost:7878" "$RADARR_KEY"   "/api/v3/indexerstatus"
reset_if_failed "Sonarr"   "http://localhost:8989" "$SONARR_KEY"   "/api/v3/indexerstatus"
reset_if_failed "Lidarr"   "http://localhost:8686" "$LIDARR_KEY"   "/api/v1/indexerstatus"
