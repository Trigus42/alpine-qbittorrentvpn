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

## Setup packet marking to allow routing of defined ports via "$DOCKER_INTERFACE"
if [[ $SET_FWMARK == "yes" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Adding fwmark for webui."

	# Setup route for qBittorrent webui using set-mark to route traffic for port 8080 to "$DOCKER_INTERFACE"
	echo "8080    webui" >> /etc/iproute2/rt_tables
	ip rule add fwmark 1 table webui
	ip route add default via "$DEFAULT_GATEWAY" table webui
	ip -6 rule add fwmark 1 table webui
	ip -6 route add default via "$DEFAULT_GATEWAY" table webui

	# Add mark for traffic on port 8080 (used by the web interface)
	nft add table inet mark
	nft add chain inet mark output { type route hook output priority 0 \; }
	nft add rule inet mark output tcp dport 8080 mark set 1
	nft add rule inet mark output tcp sport 8080 mark set 1
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
# nft rules

# Add inet table
nft add table inet filter

# Add chains to the table
nft add chain inet filter input { type filter hook input priority 0 \;  policy drop \; }
nft add chain inet filter output { type filter hook output priority 0 \;  policy drop \; }


## Input

nft add rule inet filter input iifname $VPN_DEVICE_TYPE accept comment \"Accept input from tunnel adapter\"
nft add rule inet filter input ip saddr $DOCKER_NETWORK_CIDR ip daddr $DOCKER_NETWORK_CIDR accept comment \"Accept input from internal Docker network\"
nft add rule inet filter input iifname $DOCKER_INTERFACE ip protocol $VPN_PROTOCOL sport $VPN_PORT ip saddr $VPN_REMOTE accept comment \"Accept input of VPN gateway\"
nft add rule inet filter input iifname $DOCKER_INTERFACE tcp dport 8080 accept comment \"Accept input to qBittorrent webui port\"
nft add rule inet filter input iifname lo accept comment \"Accept input to internal loopback\"

# Additional port list for scripts or container linking
if [[ -n "$ADDITIONAL_PORTS" ]]; then
	IFS=',' read -ra additional_port_list <<< "$ADDITIONAL_PORTS"

	for additional_port_item in "${additional_port_list[@]}"; do
		additional_port_item=$(echo "$additional_port_item" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Adding additional incoming port $additional_port_item for $DOCKER_INTERFACE"
		nft add rule inet filter input iifname $DOCKER_INTERFACE tcp dport $additional_port_item accept comment \"Accept input to additional port\"
	done
fi


## Output

nft add rule inet filter output oifname $VPN_DEVICE_TYPE accept comment \"Accept output to tunnel adapter\"
nft add rule inet filter output ip saddr $DOCKER_NETWORK_CIDR ip daddr $DOCKER_NETWORK_CIDR accept comment \"Accept output to internal Docker network\"
nft add rule inet filter output oifname $DOCKER_INTERFACE ip protocol $VPN_PROTOCOL dport $VPN_PORT ip daddr $VPN_REMOTE accept comment \"Accept output of VPN gateway\"
nft add rule inet filter output oifname $DOCKER_INTERFACE tcp sport 8080 accept comment \"Accept output from qBittorrent webui port\"
nft add rule inet filter output iifname lo accept comment \"Accept output to internal loopback\"

# Additional port list for scripts or container linking
if [[ -n "$ADDITIONAL_PORTS" ]]; then
	IFS=',' read -ra additional_port_list <<< "$ADDITIONAL_PORTS"

	for additional_port_item in "${additional_port_list[@]}"; do
		additional_port_item=$(echo "$additional_port_item" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Adding additional outgoing port $additional_port_item for $DOCKER_INTERFACE"
		nft add rule inet filter output oifname $DOCKER_INTERFACE tcp sport $additional_port_item accept comment \"Accept output from additional port\"
	done
fi

if [[ "$DEBUG" == "yes" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] nft ruleset defined as follows..."
	echo "--------------------"
	nft list ruleset
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
