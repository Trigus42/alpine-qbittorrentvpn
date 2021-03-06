#!/usr/bin/with-contenv bash
# shellcheck shell=bash

##########
# Host network mode?

# Check for presence of network interface docker0
check_network=$(ifconfig | grep docker0 || true)

# If network interface docker0 is present then we are running in host mode and thus must exit
if [[ -n "${check_network}" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] Network type detected as 'Host', this will cause major issues, please stop the container and switch back to 'Bridge' mode"
	# Sleep so it wont 'spam restart'
	sleep 5
	exit 1
fi

##########
# LAN network

LAN_NETWORK=$(echo "${LAN_NETWORK}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
export LAN_NETWORK

if [[ -n "${LAN_NETWORK}" ]]; then
    echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] LAN_NETWORK defined as '${LAN_NETWORK}'"
else
    echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] LAN_NETWORK not defined (via -e LAN_NETWORK)"
fi

##########
# Network environment

# Identify docker bridge interface name (probably eth0)
DOCKER_INTERFACE="$(netstat -ie | grep -vE "lo" | sed -n '1!p' | grep -P -o -m 1 '^[\w]+')"
if [[ "${DEBUG}" == "yes" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] Docker interface defined as ${DOCKER_INTERFACE}"
fi

# Identify ip of docker bridge interface
docker_ip="$(ip -4 addr show "${DOCKER_INTERFACE}" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')"
if [[ "${DEBUG}" == "yes" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] Docker IP defined as ${docker_ip}"
fi

# Identify netmask of docker bridge interface
docker_mask=$(ifconfig "${DOCKER_INTERFACE}" | grep -o "Mask:[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*" | grep -o "[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*")
if [[ "${DEBUG}" == "yes" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] Docker netmask defined as ${docker_mask}"
fi

# Convert netmask into CIDR format
DOCKER_NETWORK_CIDR=$(ipcalc "${docker_ip}" "${docker_mask}" | grep -P -o -m 1 "(?<=Network:)\s+[^\s]+" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Docker network defined as ${DOCKER_NETWORK_CIDR}"

# Get default gateway of interfaces as looping through them
DEFAULT_GATEWAY=$(ip -4 route list 0/0 | cut -d ' ' -f 3)
if [[ "${DEBUG}" == "yes" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] Default gateway defined as ${DEFAULT_GATEWAY}"
fi


##########
# PUID/PGID

if [[ -z "${PUID}" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] PUID not defined. Defaulting to 1000"
	export PUID="1000"
else
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] PUID defined as $PUID"
fi
if [[ -z "${PGID}" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] PGID not defined. Defaulting to 1000"
	export PGID="1000"
else
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] PGID defined as $PGID"
fi

# Check if the PUID exists, if not create the user with the name 'qbittorrent'
if [[ "$(getent passwd "$PUID" | cut -d: -f1)" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] An user with PUID $PUID already exists in /etc/passwd, nothing to do."
else
	if [[ "$(getent passwd "qbittorrent" | cut -d: -f3)" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] An user with PUID $PUID does not exist, changing PUID of user 'qbittorrent' to $PUID"
		deluser qbittorrent
		adduser -D -g qbittorrent -u "$PUID" qbittorrent
	else
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] An user with PUID $PUID does not exist, adding an user called 'qbittorrent' with PUID $PUID"
		adduser -D -u "$PUID" qbittorrent
	fi
fi

##########
# VPN

VPN_ENABLED=$(echo "${VPN_ENABLED,,}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
export VPN_ENABLED

if [[ -n "${VPN_ENABLED}" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] VPN_ENABLED defined as '${VPN_ENABLED}'"
else
	echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] VPN_ENABLED not defined (via -e VPN_ENABLED), defaulting to 'yes'"
	export VPN_ENABLED="yes"
fi

if [[ $VPN_ENABLED != "no" ]]; then
    # Check if VPN_TYPE is set.
	if [[ -z "${VPN_TYPE}" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] VPN_TYPE not set, defaulting to Wireguard."
		export VPN_TYPE="wireguard"
    elif [[ "${VPN_TYPE}" != "openvpn" && "${VPN_TYPE}" != "wireguard" ]]; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] VPN_TYPE not set, as 'wireguard' or 'openvpn', defaulting to Wireguard."
		export VPN_TYPE="wireguard"
	else
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] VPN_TYPE defined as '${VPN_TYPE}'"
	fi
elif [[ $VPN_ENABLED == "no" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] You have set the VPN to disabled, your connection will NOT be secure."
fi

##########
# Nameservers

NAME_SERVERS=$(echo "${NAME_SERVERS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
export NAME_SERVERS

if [[ -n "${NAME_SERVERS}" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] NAME_SERVERS defined as '${NAME_SERVERS}'"
else
	echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] NAME_SERVERS not defined (via -e NAME_SERVERS), defaulting to CloudFlare and Google name servers"
	export NAME_SERVERS="1.1.1.1,8.8.8.8,1.0.0.1,8.8.4.4"
fi

# Split comma seperated string into list from NAME_SERVERS env variable
IFS=',' read -ra name_server_list <<< "${NAME_SERVERS}"

# Process name servers in the list
for name_server_item in "${name_server_list[@]}"; do
	# strip whitespace from start and end of name_server_item
	name_server_item=$(echo "${name_server_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Adding ${name_server_item} to resolv.conf"
	echo "nameserver ${name_server_item}" >> /etc/resolv.conf
done

##########
# Save envirnonment variables

CONT_INIT_ENV="/var/run/s6/container_environment"
mkdir -p $CONT_INIT_ENV
export_vars=("LAN_NETWORK" "DOCKER_INTERFACE" "DOCKER_NETWORK_CIDR" "DEFAULT_GATEWAY" "PUID" "PGID" "VPN_TYPE")

for name in "${export_vars[@]}"; do
	echo -n "${!name}" > "$CONT_INIT_ENV/$name"
done
