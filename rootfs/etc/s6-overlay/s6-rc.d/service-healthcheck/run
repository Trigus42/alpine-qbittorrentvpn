#!/command/with-contenv bash
# shellcheck shell=bash

# shellcheck disable=SC1091
source /scripts/helper/functions.sh
# Wait until qbittorrent-nox is up
while ! (pgrep -o qbittorrent-nox >/dev/null 2>&1); do
    sleep 0.1
done
qbittorrentpid=$(pgrep -o qbittorrent-nox)
echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] qBittorrent started with PID $qbittorrentpid"

## Run

if [[ $VPN_ENABLED != "no" ]]; then
    ( while :; do
        if [[ $VPN_ENABLED != "no" ]]; then
            # Check if it is possible to bypass the VPN
            if (ping -I "$DOCKER_INTERFACE" -c 1 "$HEALTH_CHECK_HOST" > /dev/null 2>&1) || (ping -I "$DOCKER_INTERFACE" -c 1 "8.8.8.8" > /dev/null 2>&1); then
                echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] Firewall is down! Killing qBittorrent!"
                stop_container
            fi
        fi
    done ) &
fi

while :; do
    # Check if HEALTH_CHECK_HOST is reachable
    if ! ping_output=$(ping -c 1 -w "$HEALTH_CHECK_TIMEOUT" "$HEALTH_CHECK_HOST" 2>&1); then
        if [[ "$DEBUG" == "yes" ]]; then
            echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] Last failed ping:"
            echo "--------------------"
            echo "$ping_output"
            echo "--------------------"
        fi

        echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] Network is down. Exiting.."
        exit 1
    fi

    sleep "${HEALTH_CHECK_INTERVAL}"
done
