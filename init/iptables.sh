#!/bin/bash
# Wait until tunnel is up

while : ; do
	tunnelstat=$(netstat -ie | grep -E "tun|tap|wg")
	if [[ -n "${tunnelstat}" ]]; then
		break
	else
		sleep 1
	fi
done

# identify docker bridge interface name (probably eth0)
docker_interface="$(netstat -ie | grep -vE "lo|tun|tap|wg" | sed -n '1!p' | grep -P -o -m 1 '^[\w]+')"
if [[ "${DEBUG}" == "yes" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] Docker interface defined as ${docker_interface}"
fi

# identify ip for docker bridge interface
docker_ip="$(ip -4 addr show "${docker_interface}" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')"
if [[ "${DEBUG}" == "yes" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] Docker IP defined as ${docker_ip}"
fi

# identify netmask for docker bridge interface
docker_mask=$(ifconfig "${docker_interface}" | grep -o "Mask:[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*" | grep -o "[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*")
if [[ "${DEBUG}" == "yes" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] Docker netmask defined as ${docker_mask}"
fi

# convert netmask into cidr format
docker_network_cidr=$(ipcalc "${docker_ip}" "${docker_mask}" | grep -P -o -m 1 "(?<=Network:)\s+[^\s]+" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Docker network defined as ${docker_network_cidr}"

# ip route
###

# get default gateway of interfaces as looping through them
DEFAULT_GATEWAY=$(ip -4 route list 0/0 | cut -d ' ' -f 3)

if [[ "${DEBUG}" == "yes" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] Modules currently loaded for kernel:"
	echo "--------------------"
	lsmod
	echo "--------------------"
fi

# split comma separated string into list from LAN_NETWORK env variable
IFS=',' read -ra lan_network_list <<< "${LAN_NETWORK}"

# process lan networks in the list
for lan_network_item in "${lan_network_list[@]}"; do
	# strip whitespace from start and end of lan_network_item
	lan_network_item=$(echo "${lan_network_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Adding ${lan_network_item} as route via docker ${docker_interface}" 
	ip route add "${lan_network_item}" via "${DEFAULT_GATEWAY}" dev "${docker_interface}" &> /dev/null

	ip_route_add_exit_code=$?

	if [[ $ip_route_add_exit_code != 0 && $SET_FWMARK == "yes" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] Error adding route for $lan_network_item. The web interface will still be reachable due to fwmark. However this is known to cause issues."
	elif [[ $ip_route_add_exit_code != 0 ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] Error adding route for $lan_network_item. The web interface won't be reachable for the affected network"
	fi
done

## Setup iptables marks to allow routing of defined ports via "${docker_interface}"

# check we have iptable_mangle, if so setup fwmark
lsmod | grep iptable_mangle &> /dev/null
iptable_mangle_exit_code=$?

if [[ $iptable_mangle_exit_code == 0 ]]; then
	if [[ $SET_FWMARK == "yes" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Adding fwmark for webui."

		# setup route for qBittorrent webui using set-mark to route traffic for port 8080 to "${docker_interface}"
		echo "8080    webui" >> /etc/iproute2/rt_tables
		ip rule add fwmark 1 table webui
		ip route add default via "${DEFAULT_GATEWAY}" table webui

		# add mark for traffic on port 8080 (used by the web interface)
		iptables -t mangle -A OUTPUT -p tcp --dport 8080 -j MARK --set-mark 1
		iptables -t mangle -A OUTPUT -p tcp --sport 8080 -j MARK --set-mark 1
	fi
elif [[ $SET_FWMARK == "yes" ]]; then
	echo "[ERROR] SET_FWMARK is set to 'yes' but no iptable_mangle support detected."
	sleep 10
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

# input iptable rules
###

# set policy to drop ipv4 for input
iptables -P INPUT DROP

# set policy to drop ipv6 for input
ip6tables -P INPUT DROP 1>&- 2>&-

# accept input to tunnel adapter
iptables -A INPUT -i "${VPN_DEVICE_TYPE}" -m comment --comment "Accept input from tunnel adapter" -j ACCEPT

# accept input from/to internal docker network
iptables -A INPUT -s "${docker_network_cidr}" -d "${docker_network_cidr}" -m comment --comment "Accept input from internal Docker network" -j ACCEPT

# accept input to vpn gateway
iptables -A INPUT -i "${docker_interface}" -p "$VPN_PROTOCOL" --sport "$VPN_PORT" -m comment --comment "Accept input of VPN gateway" -j ACCEPT

# accept input to qBittorrent webui port
iptables -A INPUT -i "${docker_interface}" -p tcp --dport 8080 -m comment --comment "Accept input to qBittorrent webui port" -j ACCEPT

# additional port list for scripts or container linking
if [[ -n "${ADDITIONAL_PORTS}" ]]; then
	# split comma separated string into list from ADDITIONAL_PORTS env variable
	IFS=',' read -ra additional_port_list <<< "${ADDITIONAL_PORTS}"

	# process additional ports in the list
	for additional_port_item in "${additional_port_list[@]}"; do

		# strip whitespace from start and end of additional_port_item
		additional_port_item=$(echo "${additional_port_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Adding additional incoming port ${additional_port_item} for ${docker_interface}"

		# accept input to additional port for "${docker_interface}"
		iptables -A INPUT -i "${docker_interface}" -p tcp --dport "${additional_port_item}" -m comment --comment "Accept input to additional port" -j ACCEPT
	done
fi

# accept input icmp (ping)
iptables -A INPUT -p icmp --icmp-type echo-reply -m comment --comment "Accept ICMP (ping)" -j ACCEPT

# accept input to local loopback
iptables -A INPUT -i lo -m comment --comment "Accept input to internal loopback" -j ACCEPT

# output iptable rules
###

# set policy to drop ipv4 for output
iptables -P OUTPUT DROP

# set policy to drop ipv6 for output
ip6tables -P OUTPUT DROP 1>&- 2>&-

iptables -A OUTPUT -o "${VPN_DEVICE_TYPE}" -m comment --comment "Accept output to tunnel adapter" -j ACCEPT

# accept output to/from internal docker network
iptables -A OUTPUT -s "${docker_network_cidr}" -d "${docker_network_cidr}" -m comment --comment "Accept output to internal Docker network" -j ACCEPT

# accept output from vpn gateway
iptables -A OUTPUT -o "${docker_interface}" -p "$VPN_PROTOCOL" --dport "$VPN_PORT" -m comment --comment "Accept output of VPN gateway" -j ACCEPT

# accept output from qBittorrent webui port - used for lan access
iptables -A OUTPUT -o "${docker_interface}" -p tcp --sport 8080 -m comment --comment "Accept output from qBittorrent webui port" -j ACCEPT

# additional port list for scripts or container linking
if [[ -n "${ADDITIONAL_PORTS}" ]]; then
	# split comma separated string into list from ADDITIONAL_PORTS env variable
	IFS=',' read -ra additional_port_list <<< "${ADDITIONAL_PORTS}"

	# process additional ports in the list
	for additional_port_item in "${additional_port_list[@]}"; do

		# strip whitespace from start and end of additional_port_item
		additional_port_item=$(echo "${additional_port_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Adding additional outgoing port ${additional_port_item} for ${docker_interface}"

		# accept output to additional port for lan interface
		iptables -A OUTPUT -o "${docker_interface}" -p tcp --sport "${additional_port_item}" -m comment --comment "Accept output from additional port" -j ACCEPT

	done
fi

# accept output for icmp (ping)
iptables -A OUTPUT -p icmp --icmp-type echo-request -m comment --comment "Accept ICMP (ping)" -j ACCEPT

# accept output from local loopback adapter
iptables -A OUTPUT -o lo -m comment --comment "Accept output from internal loopback" -j ACCEPT

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

exec /bin/bash /init/qbittorrent.sh
