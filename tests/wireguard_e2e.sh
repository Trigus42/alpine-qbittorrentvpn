#!/bin/bash
set -e

cleanup() {
    docker compose -f tests/docker-compose-wg-e2e.yml down --volumes --remove-orphans || true
}

if [[ "$1" == "--build" ]]; then
    echo "Building qbittorrentvpn:test"
    docker build -t qbittorrentvpn:test .
fi

echo "Cleaning up any old state..."
cleanup

echo "Starting wireguard..."
docker compose -f tests/docker-compose-wg-e2e.yml up -d wireguard

# Wait for wireguard config to be generated
MAX_W_WAIT=30
W_WAIT=0
while ! docker exec wireguard sh -c "test -f /config/peer1/peer1.conf" && [ $W_WAIT -lt $MAX_W_WAIT ]; do
    echo "Waiting for wg-config..."
    sleep 2
    ((W_WAIT+=2))
done

if ! docker exec wireguard sh -c "test -f /config/peer1/peer1.conf"; then
    echo "Failed to generate wireguard configuration"
    exit 1
fi

echo "Starting qbittorrentvpn..."
docker compose -f tests/docker-compose-wg-e2e.yml up -d qbittorrentvpn

# Wait for qBittorrent WebUI to become responsive
echo "Waiting for qbittorrent WebUI..."
MAX_Q_WAIT=60
Q_WAIT=0
while ! curl -s "http://127.0.0.1:8080/api/v2/app/version" > /dev/null; do
    echo "Waiting for API to be responsive..."
    sleep 2
    ((Q_WAIT+=2))
    if [ $Q_WAIT -gt $MAX_Q_WAIT ]; then
        echo "Timeout waiting for WebUI"
        docker logs qbittorrentvpn
        exit 1
    fi
done

echo "Authenticating..."
COOKIE=$(curl -i --header "Referer: http://127.0.0.1:8080" --data "username=admin&password=adminadmin" http://127.0.0.1:8080/api/v2/auth/login | grep "set-cookie" | awk '{print $2}')
if [ -z "$COOKIE" ]; then
    echo "Failed to authenticate"
    exit 1
fi

echo "Adding test magnet link..."
curl -s -X POST -H "Cookie: ${COOKIE}" --data "urls=magnet:?xt=urn:btih:31337..." http://127.0.0.1:8080/api/v2/torrents/add

echo "Waiting for connection status..."
MAX_C_WAIT=60
C_WAIT=0
SUCCESS=false

while [ $C_WAIT -lt $MAX_C_WAIT ]; do
    STATUS=$(curl -s -H "Cookie: ${COOKIE}" http://127.0.0.1:8080/api/v2/sync/maindata | grep -o '"connection_status":"[^"]*"' | cut -d'"' -f4)
    if [ "$STATUS" == "connected" ] || [ "$STATUS" == "firewalled" ]; then
        echo "Connection established! Status: $STATUS"
        SUCCESS=true
        break
    fi
    echo "Current status: $STATUS"
    sleep 2
    ((C_WAIT+=2))
done

if [ "$SUCCESS" != "true" ]; then
    echo "Failed to establish VPN connection"
    docker logs qbittorrentvpn
    cleanup
    exit 1
fi

echo "Test completed successfully"
cleanup
exit 0