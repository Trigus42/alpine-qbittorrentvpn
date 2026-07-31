#!/command/with-contenv bash
# shellcheck shell=bash

# shellcheck disable=SC1091
source /scripts/helper/functions.sh

# No kill switch to verify without a VPN (fail-secure: only exactly "no" skips).
if [[ $VPN_ENABLED == "no" ]]; then
	sleep infinity
fi

echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Firewall (kill switch) check running every ${FIREWALL_CHECK_INTERVAL}s."

while :; do
	# Reaching the internet over the docker interface (bypassing the VPN) means
	# the kill switch is not working.
	if (ping -I "$DOCKER_INTERFACE" -c 1 "$HEALTH_CHECK_HOST" > /dev/null 2>&1) || (ping -I "$DOCKER_INTERFACE" -c 1 "$FIREWALL_CHECK_HOST" > /dev/null 2>&1); then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] Firewall is down! Killing qBittorrent!"
		stop_container
	fi

	sleep "${FIREWALL_CHECK_INTERVAL}"
done
