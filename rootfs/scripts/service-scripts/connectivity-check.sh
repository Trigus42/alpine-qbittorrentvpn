#!/command/with-contenv bash
# shellcheck shell=bash

# shellcheck disable=SC1091
source /scripts/helper/functions.sh

# No tunnel to check without a VPN (fail-secure: only exactly "no" skips).
if [[ $VPN_ENABLED == "no" ]]; then
	sleep infinity
fi

echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Connectivity check running every ${HEALTH_CHECK_INTERVAL}s."

while :; do
	# HEALTH_CHECK_HOST reachable through the tunnel?
	if ! ping_output=$(ping -c 1 -w "$HEALTH_CHECK_TIMEOUT" "$HEALTH_CHECK_HOST" 2>&1); then
		if [[ "$DEBUG" == "yes" ]]; then
			echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] Last failed ping:"
			echo "--------------------"
			echo "$ping_output"
			echo "--------------------"
		fi

		# Exit non-zero; finish halts the container so Docker restarts it.
		echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] Network is down. Exiting.."
		exit 1
	fi

	sleep "${HEALTH_CHECK_INTERVAL}"
done
