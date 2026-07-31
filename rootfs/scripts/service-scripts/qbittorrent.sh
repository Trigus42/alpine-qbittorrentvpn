#!/command/with-contenv bash
# shellcheck shell=bash

# shellcheck disable=SC1091
source /scripts/helper/functions.sh

QBITTORRENTLOGPATH="/config/qBittorrent/data/logs"
QBITTORRENTLOG="qbittorrent.log"
DAEMON="qbittorrent-nox"

umask "${UMASK}"

# qBittorrent writes its own log here; its stdout/stderr stays attached to the
# s6 service so startup crashes are visible in the container log.
if [ ! -e "$QBITTORRENTLOGPATH" ]; then
	mkdir -p "$QBITTORRENTLOGPATH"
	chown -R "${PUID}":"${PGID}" /config/qBittorrent
fi

echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] qBittorrent writes its own log to $QBITTORRENTLOGPATH/$QBITTORRENTLOG. Startup/crash output is shown below and in the container log."

# Check if it is possible to bypass the VPN
if [[ $VPN_ENABLED != "no" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Trying to ping $HEALTH_CHECK_HOST and $FIREWALL_CHECK_HOST over the docker interface for 1 second..."

	ping_1=$(ping -w 1 -I "$DOCKER_INTERFACE" -c 1 "$HEALTH_CHECK_HOST" > /dev/null 2>&1; echo $? &)
	ping_2=$(ping -w 1 -I "$DOCKER_INTERFACE" -c 1 "$FIREWALL_CHECK_HOST" > /dev/null 2>&1; echo $? &)
	wait

	if [[ "$ping_1" == "0" ]] || [[ "$ping_2" == "0" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] Firewall is down!"
		stop_container
	else
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Success: Could not connect. This means the firewall is most likely working properly."
	fi
fi

# Exec directly (no wrapping shell) so qbittorrent-nox is the process s6
# supervises and receives SIGTERM on shutdown, exiting cleanly.
exec s6-setuidgid "$(getent passwd "$PUID" | cut -d: -f1)" "$DAEMON" --profile=/config
