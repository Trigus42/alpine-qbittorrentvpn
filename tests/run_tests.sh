#!/bin/bash
# Integration test: verifies the WireGuard VPN connection and qBittorrent networking.
# Usage:
#   bash tests/run_tests.sh           # assumes qbittorrentvpn:test image is already built
#   bash tests/run_tests.sh --build   # builds the image first (local dev)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

WEBUI_URL="http://127.0.0.1:8080"
WEBUI_PASSWORD="testpassword123"
TIMEOUT_PEER_CONF=60
TIMEOUT_WEBUI=120
TIMEOUT_CONNECTION=120

cleanup() {
    local exit_code=$?
    echo "--- Tearing down containers ---"
    docker compose down --remove-orphans 2>/dev/null || true
    rm -rf wg-config qbt-config
    exit "$exit_code"
}
trap cleanup EXIT

# Optional build step (for local dev only — CI pre-builds the image)
if [[ "${1:-}" == "--build" ]]; then
    echo "--- Building qbittorrentvpn:test image ---"
    docker build -t qbittorrentvpn:test ..
fi

echo "--- Cleaning up previous test data ---"
docker compose down --remove-orphans 2>/dev/null || true
rm -rf wg-config qbt-config
mkdir -p qbt-config/wireguard

echo "--- Starting WireGuard server ---"
docker compose up -d wireguard

echo "--- Waiting for peer1.conf to be generated (up to ${TIMEOUT_PEER_CONF}s) ---"
elapsed=0
while [ ! -f wg-config/peer1/peer1.conf ]; do
    if [ "$elapsed" -ge "$TIMEOUT_PEER_CONF" ]; then
        echo "ERROR: Timed out waiting for wg-config/peer1/peer1.conf"
        docker compose logs wireguard
        exit 1
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done
echo "peer1.conf found."

echo "--- Copying WireGuard peer config to qbittorrentvpn config directory ---"
cp wg-config/peer1/peer1.conf qbt-config/wireguard/peer1.conf

echo "--- Starting qbittorrentvpn ---"
docker compose up -d qbittorrentvpn

echo "--- Waiting for WebUI to become available (up to ${TIMEOUT_WEBUI}s) ---"
elapsed=0
while ! curl -sf "${WEBUI_URL}/api/v2/app/version" > /dev/null 2>&1; do
    if [ "$elapsed" -ge "$TIMEOUT_WEBUI" ]; then
        echo "ERROR: Timed out waiting for WebUI at ${WEBUI_URL}"
        docker compose logs qbittorrentvpn
        exit 1
    fi
    sleep 3
    elapsed=$((elapsed + 3))
done
echo "WebUI is up."

echo "--- Authenticating with WebUI ---"
COOKIE_JAR="$(mktemp)"
chmod 600 "$COOKIE_JAR"
LOGIN_RESPONSE=$(curl -sf -c "$COOKIE_JAR" "${WEBUI_URL}/api/v2/auth/login" \
    --data "username=admin&password=${WEBUI_PASSWORD}")
if [[ "$LOGIN_RESPONSE" != "Ok." ]]; then
    echo "ERROR: Login failed. Response: $LOGIN_RESPONSE"
    rm -f "$COOKIE_JAR"
    exit 1
fi
echo "Authentication successful."

echo "--- Adding magnet link to trigger peer discovery ---"
curl -sf "${WEBUI_URL}/api/v2/torrents/add" \
    -b "$COOKIE_JAR" \
    --data "urls=magnet%3A%3Fxt%3Durn%3Abtih%3A0000000000000000000000000000000000000001"

echo "--- Polling connection_status (up to ${TIMEOUT_CONNECTION}s) ---"
elapsed=0
while true; do
    MAINDATA=$(curl -sf "${WEBUI_URL}/api/v2/sync/maindata" -b "$COOKIE_JAR" 2>/dev/null) || true
    if [ -n "$MAINDATA" ]; then
        STATUS=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d.get('server_state',{}).get('connection_status','unknown'))" "$MAINDATA" 2>/dev/null) || STATUS="parse_error"
    else
        STATUS="no_response"
    fi
    echo "  connection_status: $STATUS (elapsed: ${elapsed}s)"

    if [[ "$STATUS" == "connected" || "$STATUS" == "firewalled" ]]; then
        echo "SUCCESS: VPN connection is working (status: $STATUS)"
        rm -f "$COOKIE_JAR"
        exit 0
    fi

    if [ "$elapsed" -ge "$TIMEOUT_CONNECTION" ]; then
        echo "FAILURE: connection_status remained '$STATUS' after ${TIMEOUT_CONNECTION}s"
        docker compose logs qbittorrentvpn
        rm -f "$COOKIE_JAR"
        exit 1
    fi

    sleep 5
    elapsed=$((elapsed + 5))
done
