#!/usr/bin/with-contenv bash
# shellcheck shell=bash

##########
# Skip - Only needed if VPN is enabled

if [[ $VPN_ENABLED == "no" ]]; then
    exit 0
fi

##########
# Network environment

# Identify docker bridge interface name (probably eth0)
DOCKER_INTERFACE="$(netstat -ie | grep -vE "lo|tun|tap|wg|${VPN_CONFIG_NAME}" | sed -n '1!p' | grep -P -o -m 1 '^[\w]+')"
if [[ "${DEBUG}" == "yes" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] Docker interface defined as ${DOCKER_INTERFACE}"
fi

# Identify ip for docker bridge interface
docker_ip="$(ip -4 addr show "${DOCKER_INTERFACE}" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')"
if [[ "${DEBUG}" == "yes" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] Docker IP defined as ${docker_ip}"
fi

# Identify netmask for docker bridge interface
docker_mask=$(ifconfig "${DOCKER_INTERFACE}" | grep -o "Mask:[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*" | grep -o "[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*")
if [[ "${DEBUG}" == "yes" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] Docker netmask defined as ${docker_mask}"
fi

# Convert netmask into CIDR format
docker_network_cidr=$(ipcalc "${docker_ip}" "${docker_mask}" | grep -P -o -m 1 "(?<=Network:)\s+[^\s]+" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Docker network defined as ${docker_network_cidr}"

##########
# Packet routing

# get default gateway of interfaces as looping through them
DEFAULT_GATEWAY=$(ip -4 route list 0/0 | cut -d ' ' -f 3)

# Split comma separated string into list from LAN_NETWORK env variable
IFS=',' read -ra lan_network_list <<< "${LAN_NETWORK}"

# Process lan networks in the list
for lan_network_item in "${lan_network_list[@]}"; do
	# Strip whitespace from start and end of lan_network_item
	lan_network_item=$(echo "${lan_network_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Adding ${lan_network_item} as route via docker ${DOCKER_INTERFACE}" 
	ip route add "${lan_network_item}" via "${DEFAULT_GATEWAY}" dev "${DOCKER_INTERFACE}" &> /dev/null

	ip_route_add_exit_code=$?

	if [[ $ip_route_add_exit_code != 0 && $SET_FWMARK == "yes" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] Error adding route for $lan_network_item. The web interface will still be reachable due to fwmark. However this is known to cause issues."
	elif [[ $ip_route_add_exit_code != 0 ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] Error adding route for $lan_network_item. The web interface won't be reachable for the affected network"
	fi
done

## Setup iptables marks to allow routing of defined ports via "${DOCKER_INTERFACE}"

# check we have iptable_mangle, if so setup fwmark
lsmod | grep iptable_mangle &> /dev/null
iptable_mangle_exit_code=$?

if [[ $iptable_mangle_exit_code == 0 ]]; then
	if [[ $SET_FWMARK == "yes" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Adding fwmark for webui."

		# Setup route for qBittorrent webui using set-mark to route traffic for port 8080 to "${DOCKER_INTERFACE}"
		echo "8080    webui" >> /etc/iproute2/rt_tables
		ip rule add fwmark 1 table webui
		ip route add default via "${DEFAULT_GATEWAY}" table webui

		# Add mark for traffic on port 8080 (used by the web interface)
		iptables -t mangle -A OUTPUT -p tcp --dport 8080 -j MARK --set-mark 1
		iptables -t mangle -A OUTPUT -p tcp --sport 8080 -j MARK --set-mark 1
	fi
elif [[ $SET_FWMARK == "yes" ]]; then
	echo "[ERROR] SET_FWMARK is set to 'yes' but no iptable_mangle support detected."
	sleep 5
	exit 1
fi

if [[ "${DEBUG}" == "yes" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] 'main' routing table defined as follows..."
	echo "--------------------"
	ip route show table main
	echo "--------------------"
	echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] ip rules defined as follows..."
	echo "--------------------"
	ip rule
	echo "--------------------"
fi

##########
# Iptable rules

## Input

# Accept input to tunnel adapter
iptables -A INPUT -i "${VPN_DEVICE_TYPE}" -m comment --comment "Accept input from tunnel adapter" -j ACCEPT

# Accept input from/to internal docker network
iptables -A INPUT -s "${docker_network_cidr}" -d "${docker_network_cidr}" -m comment --comment "Accept input from internal Docker network" -j ACCEPT

# Accept input to vpn gateway
iptables -A INPUT -i "${DOCKER_INTERFACE}" -p "$VPN_PROTOCOL" --sport "$VPN_PORT" -s "${VPN_REMOTE}" -m comment --comment "Accept input of VPN gateway" -j ACCEPT

# Accept input to qBittorrent webui port
iptables -A INPUT -i "${DOCKER_INTERFACE}" -p tcp --dport 8080 -m comment --comment "Accept input to qBittorrent webui port" -j ACCEPT

# Additional port list for scripts or container linking
if [[ -n "${ADDITIONAL_PORTS}" ]]; then
	# Split comma separated string into list from ADDITIONAL_PORTS env variable
	IFS=',' read -ra additional_port_list <<< "${ADDITIONAL_PORTS}"

	# Process additional ports in the list
	for additional_port_item in "${additional_port_list[@]}"; do

		# Strip whitespace from start and end of additional_port_item
		additional_port_item=$(echo "${additional_port_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Adding additional incoming port ${additional_port_item} for ${DOCKER_INTERFACE}"

		# Accept input to additional port for "${DOCKER_INTERFACE}"
		iptables -A INPUT -i "${DOCKER_INTERFACE}" -p tcp --dport "${additional_port_item}" -m comment --comment "Accept input to additional port" -j ACCEPT
	done
fi

# Accept input to local loopback
iptables -A INPUT -i lo -m comment --comment "Accept input to internal loopback" -j ACCEPT

## Output

# Accept output to tunnel adapter
iptables -A OUTPUT -o "${VPN_DEVICE_TYPE}" -m comment --comment "Accept output to tunnel adapter" -j ACCEPT

# Accept output to/from internal docker network
iptables -A OUTPUT -s "${docker_network_cidr}" -d "${docker_network_cidr}" -m comment --comment "Accept output to internal Docker network" -j ACCEPT

# Accept output from vpn gateway
iptables -A OUTPUT -o "${DOCKER_INTERFACE}" -p "$VPN_PROTOCOL" --dport "$VPN_PORT" -d "${VPN_REMOTE}" -m comment --comment "Accept output of VPN gateway" -j ACCEPT

# Accept output from qBittorrent webui port - used for lan access
iptables -A OUTPUT -o "${DOCKER_INTERFACE}" -p tcp --sport 8080 -m comment --comment "Accept output from qBittorrent webui port" -j ACCEPT

# Additional port list for scripts or container linking
if [[ -n "${ADDITIONAL_PORTS}" ]]; then
	# Split comma separated string into list from ADDITIONAL_PORTS env variable
	IFS=',' read -ra additional_port_list <<< "${ADDITIONAL_PORTS}"

	# Process additional ports in the list
	for additional_port_item in "${additional_port_list[@]}"; do

		# Strip whitespace from start and end of additional_port_item
		additional_port_item=$(echo "${additional_port_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Adding additional outgoing port ${additional_port_item} for ${DOCKER_INTERFACE}"

		# Accept output to additional port for lan interface
		iptables -A OUTPUT -o "${DOCKER_INTERFACE}" -p tcp --sport "${additional_port_item}" -m comment --comment "Accept output from additional port" -j ACCEPT

	done
fi

# Accept output from local loopback adapter
iptables -A OUTPUT -o lo -m comment --comment "Accept output from internal loopback" -j ACCEPT

## Policies

# Set policy to drop ipv4 for input
iptables -P INPUT DROP

# Set policy to drop ipv6 for input
ip6tables -P INPUT DROP 1>&- 2>&-

# Set policy to drop ipv4 for output
iptables -P OUTPUT DROP

# Set policy to drop ipv6 for output
ip6tables -P OUTPUT DROP 1>&- 2>&-

if [[ "${DEBUG}" == "yes" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] iptables table 'filter' defined as follows..."
	echo "--------------------"
	iptables -S -t filter
	echo "--------------------"

	echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] iptables table 'mangle' defined as follows..."
	echo "--------------------"
	iptables -S -t mangle
	echo "--------------------"
fi

##########
# Save envirnonment variables

CONT_INIT_ENV="/var/run/s6/container_environment"
mkdir -p $CONT_INIT_ENV
export_vars=("DOCKER_INTERFACE")

for name in "${export_vars[@]}"; do
	echo -n "${!name}" > "$CONT_INIT_ENV/$name"
done
