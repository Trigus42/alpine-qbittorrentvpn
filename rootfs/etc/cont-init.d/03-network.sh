#!/usr/bin/with-contenv bash
# shellcheck shell=bash

##########
# Skip - Only needed if VPN is enabled

if [[ $VPN_ENABLED == "no" ]]; then
    exit 0
fi

##########
# Packet routing

# Split comma separated string into list from LAN_NETWORK env variable
IFS=',' read -ra lan_network_list <<< "$LAN_NETWORK"

# Process lan networks in the list
for lan_network_item in "${lan_network_list[@]}"; do
	# Strip whitespace from start and end of lan_network_item
	lan_network_item=$(echo "$lan_network_item" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Adding $lan_network_item as route via docker $DOCKER_INTERFACE" 
	ip route add "$lan_network_item" via "$DEFAULT_GATEWAY" dev "$DOCKER_INTERFACE" &> /dev/null

	ip_route_add_exit_code=$?

	if [[ $ip_route_add_exit_code != 0 && $SET_FWMARK == "yes" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] Error adding route for $lan_network_item. The web interface will still be reachable due to fwmark. However this is known to cause issues."
	elif [[ $ip_route_add_exit_code != 0 ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] Error adding route for $lan_network_item. The web interface won't be reachable for the affected network"
	fi
done

## Setup iptables marks to allow routing of defined ports via "$DOCKER_INTERFACE"

# check we have iptable_mangle, if so setup fwmark
lsmod | grep iptable_mangle &> /dev/null
iptable_mangle_exit_code=$?

if [[ $iptable_mangle_exit_code == 0 ]]; then
	if [[ $SET_FWMARK == "yes" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Adding fwmark for webui."

		# Setup route for qBittorrent webui using set-mark to route traffic for port 8080 to "$DOCKER_INTERFACE"
		echo "8080    webui" >> /etc/iproute2/rt_tables
		ip rule add fwmark 1 table webui
		ip route add default via "$DEFAULT_GATEWAY" table webui

		# Add mark for traffic on port 8080 (used by the web interface)
		iptables -t mangle -A OUTPUT -p tcp --dport 8080 -j MARK --set-mark 1
		iptables -t mangle -A OUTPUT -p tcp --sport 8080 -j MARK --set-mark 1
	fi
elif [[ $SET_FWMARK == "yes" ]]; then
	echo "[ERROR] SET_FWMARK is set to 'yes' but no iptable_mangle support detected."
	sleep 5
	exit 1
fi

if [[ "$DEBUG" == "yes" ]]; then
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

function add_comment_rule() {
    local rule="$1"
    if [[ "$xt_comment_exit_code" -eq 0 ]]; then
        eval $rule
    else
        # remove the comment part of the rule
        local no_comment_rule=$(echo $rule | sed -E "s/-m comment --comment \\\"[^\"]+\\\"//" | tr -d '\n')
        eval $no_comment_rule
    fi
}

# Check if xt_comment module is available
lsmod | grep xt_comment &> /dev/null
xt_comment_exit_code=$?

## Input

# Accept input to tunnel adapter
add_comment_rule "iptables -A INPUT -i $VPN_DEVICE_TYPE -m comment --comment \"Accept input from tunnel adapter\" -j ACCEPT"

# Accept input from/to internal docker network
add_comment_rule "iptables -A INPUT -s $DOCKER_NETWORK_CIDR -d $DOCKER_NETWORK_CIDR -m comment --comment \"Accept input from internal Docker network\" -j ACCEPT"

# Accept input to vpn gateway
add_comment_rule "iptables -A INPUT -i $DOCKER_INTERFACE -p $VPN_PROTOCOL --sport $VPN_PORT -s $VPN_REMOTE -m comment --comment \"Accept input of VPN gateway\" -j ACCEPT"

# Accept input to qBittorrent webui port
add_comment_rule "iptables -A INPUT -i $DOCKER_INTERFACE -p tcp --dport 8080 -m comment --comment \"Accept input to qBittorrent webui port\" -j ACCEPT"

# Additional port list for scripts or container linking
if [[ -n "$ADDITIONAL_PORTS" ]]; then
	# Split comma separated string into list from ADDITIONAL_PORTS env variable
	IFS=',' read -ra additional_port_list <<< "$ADDITIONAL_PORTS"

	# Process additional ports in the list
	for additional_port_item in "${additional_port_list[@]}"; do

		# Strip whitespace from start and end of additional_port_item
		additional_port_item=$(echo "$additional_port_item" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Adding additional incoming port $additional_port_item for $DOCKER_INTERFACE"

		# Accept input to additional port for "$DOCKER_INTERFACE"
		add_comment_rule "iptables -A INPUT -i $DOCKER_INTERFACE -p tcp --dport $additional_port_item -m comment --comment \"Accept input to additional port\" -j ACCEPT"
	done
fi

# Accept input to local loopback
add_comment_rule "iptables -A INPUT -i lo -m comment --comment \"Accept input to internal loopback\" -j ACCEPT"

## Output

# Accept output to tunnel adapter
add_comment_rule "iptables -A OUTPUT -o $VPN_DEVICE_TYPE -m comment --comment \"Accept output to tunnel adapter\" -j ACCEPT"

# Accept output to/from internal docker network
add_comment_rule "iptables -A OUTPUT -s $DOCKER_NETWORK_CIDR -d $DOCKER_NETWORK_CIDR -m comment --comment \"Accept output to internal Docker network\" -j ACCEPT"

# Accept output from vpn gateway
add_comment_rule "iptables -A OUTPUT -o $DOCKER_INTERFACE -p $VPN_PROTOCOL --dport $VPN_PORT -d $VPN_REMOTE -m comment --comment \"Accept output of VPN gateway\" -j ACCEPT"

# Accept output from qBittorrent webui port - used for lan access
add_comment_rule "iptables -A OUTPUT -o $DOCKER_INTERFACE -p tcp --sport 8080 -m comment --comment \"Accept output from qBittorrent webui port\" -j ACCEPT"

# Additional port list for scripts or container linking
if [[ -n "$ADDITIONAL_PORTS" ]]; then
	# Split comma separated string into list from ADDITIONAL_PORTS env variable
	IFS=',' read -ra additional_port_list <<< "$ADDITIONAL_PORTS"

	# Process additional ports in the list
	for additional_port_item in "${additional_port_list[@]}"; do

		# Strip whitespace from start and end of additional_port_item
		additional_port_item=$(echo "$additional_port_item" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Adding additional outgoing port $additional_port_item for $DOCKER_INTERFACE"

		# Accept output to additional port for lan interface
		add_comment_rule "iptables -A OUTPUT -o \"$DOCKER_INTERFACE\" -p tcp --sport \"$additional_port_item\" -m comment --comment \"Accept output from additional port\" -j ACCEPT"

	done
fi

# Accept output from local loopback adapter
add_comment_rule "iptables -A OUTPUT -o lo -m comment --comment \"Accept output from internal loopback\" -j ACCEPT"

## Policies

# Set policy to drop ipv4 for input
iptables -P INPUT DROP

# Set policy to drop ipv6 for input
ip6tables -P INPUT DROP 1>&- 2>&-

# Set policy to drop ipv4 for output
iptables -P OUTPUT DROP

# Set policy to drop ipv6 for output
ip6tables -P OUTPUT DROP 1>&- 2>&-

if [[ "$DEBUG" == "yes" ]]; then
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
