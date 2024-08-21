#!/command/with-contenv bash
# shellcheck shell=bash

# shellcheck disable=SC1091
source /scripts/helper/functions.sh

USER=${PUID}
GROUP=${PGID}

QBITTORRENTLOGPATH="/config/qBittorrent/data/logs"
QBITTORRENTLOG="qbittorrent.log"
DAEMON="qbittorrent-nox"
DAEMON_ARGS="--profile=/config"
DAEMONSTRING="$DAEMON $DAEMON_ARGS >> $QBITTORRENTLOGPATH/$QBITTORRENTLOG 2>&1"

umask "${UMASK}"

# Check if log path exists. If it doesn't exist, create it.
if [ ! -e $QBITTORRENTLOGPATH ]; then
	mkdir -p $QBITTORRENTLOGPATH
	chown -R "${PUID}":"${PGID}" /config/qBittorrent
fi

# Check for log file. If it doesn't exist, create it.
if [ -f $QBITTORRENTLOGPATH/$QBITTORRENTLOG ]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Logging to $QBITTORRENTLOGPATH/$QBITTORRENTLOG."
else
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Log file $QBITTORRENTLOGPATH/$QBITTORRENTLOG doesn't exist. Creating it..."
	touch "$QBITTORRENTLOGPATH/$QBITTORRENTLOG"
	if [ -f "$QBITTORRENTLOGPATH/$QBITTORRENTLOG" ]; then
		chown "$USER":"$GROUP" $QBITTORRENTLOGPATH/$QBITTORRENTLOG
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Logfile created. Logging to $QBITTORRENTLOGPATH/$QBITTORRENTLOG"
	else
		echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] Couldn't create logfile $QBITTORRENTLOGPATH/$QBITTORRENTLOG"
	fi
fi

# Check if it is possible to bypass the VPN
if [[ $VPN_ENABLED != "no" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Trying to ping 1.1.1.1 and 8.8.8.8 over the docker interface for 1 second..."

	ping_1=$(ping -w 1 -I "$DOCKER_INTERFACE" -c 1 "1.1.1.1" > /dev/null 2>&1; echo $? &)
	ping_2=$(ping -w 1 -I "$DOCKER_INTERFACE" -c 1 "8.8.8.8" > /dev/null 2>&1; echo $? &)
	wait

	if [[ "$ping_1" == "0" ]] || [[ "$ping_2" == "0" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] Firewall is down!"
		stop_container
	else
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Success: Could not connect. This means the firewall is most likely working properly."
	fi
fi

exec s6-setuidgid "$(getent passwd "$PUID" | cut -d: -f1)" /bin/bash -c "$DAEMONSTRING"
