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
	ip route add "$lan_network_item" via "$DEFAULT_IPV4_GATEWAY" dev "$DOCKER_INTERFACE" &> /dev/null

	ip_route_add_exit_code=$?

	if [[ $ip_route_add_exit_code != 0 && $SET_FWMARK == "yes" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] Error adding route for $lan_network_item. The web interface will still be reachable due to fwmark. However this is known to cause issues."
	elif [[ $ip_route_add_exit_code != 0 ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] Error adding route for $lan_network_item. The web interface won't be reachable for the affected network"
	fi
done


##########
# nft rules

# Mark outgoing packets belonging to a WebUI connection
nft "add table inet qbt-mark"
nft "add chain inet qbt-mark prerouting { type filter hook prerouting priority -150 ; }"
nft "add chain inet qbt-mark output { type route hook output priority -150 ; }"
nft "add rule inet qbt-mark prerouting iif eth0 tcp dport 8080 ct state new ct mark set 9090 counter comment \"Track new WebUI connections\""
nft "add rule inet qbt-mark output ct mark 9090 meta mark set 8080 counter comment \"Add mark to outgoing packets belonging to a WebUI connection\""

# Route WebUI traffic over "$DEFAULT_IPV4_GATEWAY"
echo "8080    webui" >> /etc/iproute2/rt_tables
ip rule add fwmark 8080 table webui
ip route add default via "$DEFAULT_IPV4_GATEWAY" table webui
ip -6 rule add fwmark 8080 table webui
ip -6 route add default via "$DEFAULT_IPV6_GATEWAY" eth0 table webui

# Add firewall table
nft add table inet firewall


## VPN_REMOTE IPs

# VPN_REMOTE is already an IPv4 address
if [[ $VPN_REMOTE =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	ipv4_addresses=("$VPN_REMOTE")
	ipv6_addresses=()
# VPN_REMOTE is already an IPv6 address
elif [[ $VPN_REMOTE =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]]; then
	ipv4_addresses=()
	ipv6_addresses=("$VPN_REMOTE")
# VPN_REMOTE is a hostname
else
	# Get a list of the IPv4 and IPv6 addresses
	ipv4_addresses=("$(dig +short A $VPN_REMOTE)")
	ipv6_addresses=("$(dig +short AAAA $VPN_REMOTE)")
fi

# Create the sets for storing the IPv4 and IPv6 addresses
nft "add set inet firewall vpn_ipv4 { type ipv4_addr ; }"
nft "add set inet firewall vpn_ipv6 { type ipv6_addr ; }"

# Add each IP address to its respective set
for address in "${ipv4_addresses[@]}"; do
  nft "add element inet firewall vpn_ipv4 { $address }"
done

for address in "${ipv6_addresses[@]}"; do
  nft "add element inet firewall vpn_ipv6 { $address }"
done


# Add chains to the table
nft "add chain inet firewall input { type filter hook input priority 0 ; policy drop ; }"
nft "add chain inet firewall output { type filter hook postrouting priority 0 ; policy drop ; }"


## Input

nft "add rule inet firewall input iifname $VPN_DEVICE_TYPE accept comment \"Accept input from VPN tunnel\""
nft "add rule inet firewall input iifname $DOCKER_INTERFACE $VPN_PROTOCOL sport $VPN_PORT ip saddr @vpn_ipv4 accept comment \"Accept input from VPN server \(IPv4\)\""
nft "add rule inet firewall input iifname $DOCKER_INTERFACE $VPN_PROTOCOL sport $VPN_PORT ip6 saddr @vpn_ipv6 accept comment \"Accept input from VPN server \(IPv6\)\""
nft "add rule inet firewall input iifname $DOCKER_INTERFACE tcp dport 8080 counter accept comment \"Accept input to the qBt WebUI\""
nft "add rule inet firewall input iifname lo accept comment \"Accept input from internal loopback\""

# Additional port list for scripts or container linking
if [[ -n "$ADDITIONAL_PORTS" ]]; then
	IFS=',' read -ra additional_port_list <<< "$ADDITIONAL_PORTS"

	for additional_port_item in "${additional_port_list[@]}"; do
		additional_port_item=$(echo "$additional_port_item" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Adding additional incoming port $additional_port_item for $DOCKER_INTERFACE"
		nft "add rule inet firewall input iifname $DOCKER_INTERFACE tcp dport $additional_port_item accept comment \"Accept input to additional port\""
	done
fi


## Output

nft "add rule inet firewall output oifname $VPN_DEVICE_TYPE accept comment \"Accept output to VPN tunnel\""
nft "add rule inet firewall output oifname $DOCKER_INTERFACE $VPN_PROTOCOL dport $VPN_PORT ip daddr @vpn_ipv4 accept comment \"Accept output to VPN server \(IPv4\)\""
nft "add rule inet firewall output oifname $DOCKER_INTERFACE $VPN_PROTOCOL dport $VPN_PORT ip6 daddr @vpn_ipv6 accept comment \"Accept output to VPN server \(IPv6\)\""
nft "add rule inet firewall output oifname $DOCKER_INTERFACE tcp sport 8080 meta mark 8080 counter accept comment \"Accept outgoing packets belonging to a WebUI connection\""
nft "add rule inet firewall output iifname lo accept comment \"Accept output to internal loopback\""

# Additional port list for scripts or container linking
if [[ -n "$ADDITIONAL_PORTS" ]]; then
	IFS=',' read -ra additional_port_list <<< "$ADDITIONAL_PORTS"

	for additional_port_item in "${additional_port_list[@]}"; do
		additional_port_item=$(echo "$additional_port_item" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Adding additional outgoing port $additional_port_item for $DOCKER_INTERFACE"
		nft "add rule inet firewall output oifname $DOCKER_INTERFACE tcp sport $additional_port_item accept comment \"Accept output from additional port\""
	done
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
