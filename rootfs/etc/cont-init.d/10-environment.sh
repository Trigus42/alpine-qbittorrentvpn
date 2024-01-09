#!/usr/bin/with-contenv bash
# shellcheck shell=bash

# shellcheck disable=SC1091
source /helper/functions.sh

##########
# Host network mode?

# Check for presence of network interface docker0
check_network=$(ifconfig | grep docker0 || true)

# If network interface docker0 is present then we are running in host mode and thus must exit
if [[ -n "${check_network}" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] Network type detected as 'Host', this will cause major issues, please stop the container and switch back to 'Bridge' mode"
	stop_container
fi

##########
# Deprecation warnings

if [[ -n "${LAN_NETWORK}" ]]; then
    echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] LAN_NETWORK is deprecated, might not work in future versions and is no longer needed. Obmit or use WEBUI_ALLOWED_NETWORKS to restrict access instead"
fi
if [[ -n "${ADDITIONAL_PORTS}" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] ADDITIONAL_PORTS is deprecated and might not work in future versions. Add a custom firewall script instead"
fi

##########
# WEBUI_ALLOWED_NETWORKS

if [[ -n "${WEBUI_ALLOWED_NETWORKS}" ]]; then
    echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] WEBUI_ALLOWED_NETWORKS is defined as $WEBUI_ALLOWED_NETWORKS"
fi

#########
# Healthcheck

DEFAULT_HOST="1.1.1.1"
DEFAULT_INTERVAL=5
DEFAULT_TIMEOUT=5

# If HEALTH_CHECK_HOST is zero (not set) use DEFAULT_HOST
if [[ -z "${HEALTH_CHECK_HOST}" ]]; then
    echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] HEALTH_CHECK_HOST is not set. Using default host ${DEFAULT_HOST}"
    HEALTH_CHECK_HOST=${DEFAULT_HOST}
fi

# If HEALTH_CHECK_INTERVAL is zero (not set) use DEFAULT_INTERVAL
if [[ -z "${HEALTH_CHECK_INTERVAL}" ]]; then
    echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] HEALTH_CHECK_INTERVAL is not set. Using default interval of ${DEFAULT_INTERVAL}s"
    HEALTH_CHECK_INTERVAL=${DEFAULT_INTERVAL}
fi

# If HEALTH_CHECK_TIMEOUT is zero (not set) use DEFAULT_TIMEOUT
if [[ -z "${HEALTH_CHECK_TIMEOUT}" ]]; then
    echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] HEALTH_CHECK_TIMEOUT is not set. Using default interval of ${DEFAULT_TIMEOUT}s"
    HEALTH_CHECK_TIMEOUT=${DEFAULT_TIMEOUT}
fi

##########
# Network environment

# Identify docker bridge interface name (probably eth0)
DOCKER_INTERFACE="$(netstat -ie | grep -vE "lo" | sed -n '1!p' | grep -P -o -m 1 '^[\w]+')"
if [[ "${DEBUG}" == "yes" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] Docker interface defined as ${DOCKER_INTERFACE}"
fi

# Identify IPv4 address of docker bridge interface
docker_ipv4_cidr="$(ip -4 addr show dev "${DOCKER_INTERFACE}" | grep -oP '(?<=inet\s)\d+(\.\d+){3}\/\d+')"

# Identify link-local IPv6 address of docker bridge interface
docker_ipv6_ula_cidr="$(ip -6 addr show dev "${DOCKER_INTERFACE}" | grep -oP '(?<=inet6\s)fd[0-9a-f:]+\/[0-9]+')"


# IPv4
if [ -n "$docker_ipv4_cidr" ]; then
	# Get address without mask
	docker_ipv4="$(grep -oP '^[^\/]+' <<< "${docker_ipv4_cidr}")"
	if [[ "${DEBUG}" == "yes" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] Docker IPv4 address defined as ${docker_ipv4}"
	fi

	# Calculate CIDR network notation
	DOCKER_IPV4_NETWORK_CIDR=$(ipcalc "${docker_ipv4_cidr}" | grep -P -o -m 1 "(?<=Network:)\s+[^\s]+" | sed -e 's/\s//g')
	if [[ "${DEBUG}" == "yes" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Docker IPv4 network defined as ${DOCKER_IPV4_NETWORK_CIDR}"
	fi

	# Get default gateway
	DEFAULT_IPV4_GATEWAY=$(ip -4 route list 0/0 | cut -d ' ' -f 3 | head -n 1)
	if [[ "${DEBUG}" == "yes" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] Default IPv4 gateway defined as ${DEFAULT_IPV4_GATEWAY}"
	fi
fi

# IPv6
if [ -n "$docker_ipv6_ula_cidr" ]; then
	# Get address without mask
	docker_ipv6_ula="$(grep -oP '^[^\/]+' <<< "${docker_ipv6_ula_cidr}")"
	if [[ "${DEBUG}" == "yes" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] Docker unique-local IPv6 address defined as ${docker_ipv6_ula}"
	fi

	# Calculate CIDR network notation
	DOCKER_IPV6_ULA_NETWORK_CIDR=$(ipcalc "${docker_ipv6_ula_cidr}" | grep -P -o -m 1 "(?<=Network:)\s+[^\s]+" | sed -e 's/\s//g')
	if [[ "${DEBUG}" == "yes" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Docker IPv6 network defined as ${DOCKER_IPV6_ULA_NETWORK_CIDR}"
	fi

	# Get default gateway
	DEFAULT_IPV6_GATEWAY=$(ip -6 route list ::0/0 | cut -d ' ' -f 3 | head -n 1)
	if [[ "${DEBUG}" == "yes" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] Default IPv6 gateway defined as ${DEFAULT_IPV6_GATEWAY}"
	fi
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
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] VPN_ENABLED not defined (via -e VPN_ENABLED), defaulting to 'yes'"
fi

if [[ $VPN_ENABLED != "no" ]]; then
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
	BIRed='\033[1;91m'
	On_IGreen='\033[0;102m'
	COLOR_RESET='\033[0m'
	echo -e "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] ${On_IGreen}${BIRed}You have set the VPN to disabled, your connection will NOT be secure.${COLOR_RESET}"
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
export_vars=("DOCKER_INTERFACE" "DOCKER_IPV4_NETWORK_CIDR" "DOCKER_IPV6_ULA_NETWORK_CIDR" "DEFAULT_IPV4_GATEWAY" "DEFAULT_IPV6_GATEWAY" "PUID" "PGID" "VPN_TYPE" "HEALTH_CHECK_HOST" "HEALTH_CHECK_INTERVAL" "HEALTH_CHECK_TIMEOUT")

for name in "${export_vars[@]}"; do
	echo -n "${!name}" > "$CONT_INIT_ENV/$name"
done
