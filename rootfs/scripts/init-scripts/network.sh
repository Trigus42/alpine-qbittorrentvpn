#!/bin/bash

# shellcheck disable=SC1091
source /scripts/helper/functions.sh

##########
# DSM/Legacy compatibility feature flags
# Set these to "yes" to enable modern features that may not work on older kernels
#
# FOR DSM USERS EXPERIENCING ISSUES:
# 1. Set LEGACY_IPTABLES=yes
# 2. Set all DSM_TEST_ENABLE_* flags to "no" 
# 3. If that works, try enabling flags one by one to identify the problematic feature
#
# Expected working configuration for older DSM systems:
# LEGACY_IPTABLES=yes
# DSM_TEST_ENABLE_IPSET=no              # Avoids ipset module dependency
# DSM_TEST_ENABLE_CONNTRACK=no          # Avoids conntrack/connmark modules
# DSM_TEST_ENABLE_POLICY_ROUTING=no     # Avoids suppress_prefixlength feature
# DSM_TEST_ENABLE_IPV6=no               # Disables all IPv6 rules
# DSM_TEST_ENABLE_ICMP_RULES=no         # Disables advanced ICMP rules
# DSM_TEST_ENABLE_MARK_MATCHING=no      # Uses simple interface-based rules

# Test individual kernel modules/features for DSM compatibility
: "${DSM_TEST_ENABLE_IPSET:=no}"              # Use ipset module instead of direct IP matching
: "${DSM_TEST_ENABLE_CONNTRACK:=no}"          # Use conntrack/connmark features  
: "${DSM_TEST_ENABLE_POLICY_ROUTING:=no}"     # Use policy routing with suppress_prefixlength
: "${DSM_TEST_ENABLE_IPV6:=no}"               # Enable IPv6 iptables rules
: "${DSM_TEST_ENABLE_ICMP_RULES:=no}"         # Enable advanced ICMP/ICMPv6 rules
: "${DSM_TEST_ENABLE_MARK_MATCHING:=no}"      # Use packet mark matching in output rules

##########
# Log DSM test configuration

if [[ "$LEGACY_IPTABLES" == "yes" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] LEGACY_IPTABLES=yes - Using legacy iptables mode"
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] DSM Test Flags:"
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO]   DSM_TEST_ENABLE_IPSET=$DSM_TEST_ENABLE_IPSET"
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO]   DSM_TEST_ENABLE_CONNTRACK=$DSM_TEST_ENABLE_CONNTRACK"
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO]   DSM_TEST_ENABLE_POLICY_ROUTING=$DSM_TEST_ENABLE_POLICY_ROUTING"
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO]   DSM_TEST_ENABLE_IPV6=$DSM_TEST_ENABLE_IPV6"
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO]   DSM_TEST_ENABLE_ICMP_RULES=$DSM_TEST_ENABLE_ICMP_RULES"
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO]   DSM_TEST_ENABLE_MARK_MATCHING=$DSM_TEST_ENABLE_MARK_MATCHING"
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] NOTE: For DSM compatibility issues, try setting all flags to 'no' first"
fi

##########
# Skip - Only needed if VPN is enabled

if [[ $VPN_ENABLED == "no" ]]; then
    exit 0
fi

##########
# nft rules

# Mark outgoing packets belonging to a WebUI connection (for routing and firewall)
if [[ "$LEGACY_IPTABLES" != "yes" ]]; then
	nft "add table inet qbt-mark"
	nft "add chain inet qbt-mark prerouting { type filter hook prerouting priority -150 ; }"
	nft "add chain inet qbt-mark output { type route hook output priority -150 ; }"
	nft "add rule inet qbt-mark prerouting tcp dport 8080 ct state new ct mark set 9090 counter comment \"Track new WebUI connections\""
	nft "add rule inet qbt-mark prerouting tcp dport 8080 meta mark set 8080 counter packets 0 bytes 0 comment \"Mark packets to pass rp_filter reverse path route lookup\""
	nft "add rule inet qbt-mark output ct mark 9090 meta mark set 8080 counter comment \"Add mark to outgoing packets belonging to a WebUI connection\""
else
	# Check if we should use advanced conntrack features or fall back to simple marking
	if [[ "$DSM_TEST_ENABLE_CONNTRACK" == "yes" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] DSM_TEST_ENABLE_CONNTRACK=yes - Using conntrack/connmark features"
		iptables -t mangle -N QBT-MARK-PREROUTING
		iptables -t mangle -N QBT-MARK-OUTPUT
		iptables -t mangle -A PREROUTING -j QBT-MARK-PREROUTING
		iptables -t mangle -A OUTPUT -j QBT-MARK-OUTPUT
		iptables -t mangle -A QBT-MARK-PREROUTING -p tcp --dport 8080 -m conntrack --ctstate NEW -j CONNMARK --set-mark 9090 -m comment --comment "Track new WebUI connections"
		iptables -t mangle -A QBT-MARK-PREROUTING -p tcp --dport 8080 -j MARK --set-mark 8080 -m comment --comment "Mark packets to pass rp_filter reverse path route lookup"
		iptables -t mangle -A QBT-MARK-OUTPUT -m connmark --mark 9090 -j MARK --set-mark 8080 -m comment --comment "Add mark to outgoing packets belonging to a WebUI connection"

		if [[ "$DSM_TEST_ENABLE_IPV6" == "yes" ]]; then
			ip6tables -t mangle -N QBT-MARK-PREROUTING
			ip6tables -t mangle -N QBT-MARK-OUTPUT
			ip6tables -t mangle -A PREROUTING -j QBT-MARK-PREROUTING
			ip6tables -t mangle -A OUTPUT -j QBT-MARK-OUTPUT
			ip6tables -t mangle -A QBT-MARK-PREROUTING -p tcp --dport 8080 -m conntrack --ctstate NEW -j CONNMARK --set-mark 9090 -m comment --comment "Track new WebUI connections"
			ip6tables -t mangle -A QBT-MARK-PREROUTING -p tcp --dport 8080 -j MARK --set-mark 8080 -m comment --comment "Mark packets to pass rp_filter reverse path route lookup"
			ip6tables -t mangle -A QBT-MARK-OUTPUT -m connmark --mark 9090 -j MARK --set-mark 8080 -m comment --comment "Add mark to outgoing packets belonging to a WebUI connection"
		fi
	else
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] DSM_TEST_ENABLE_CONNTRACK=no - Using simple packet marking (legacy mode)"
		# Fallback to simple marking like the old 03-network.sh
		# Check if iptables_mangle is available first
		lsmod | grep iptable_mangle &> /dev/null
		iptable_mangle_exit_code=$?

		if [[ $iptable_mangle_exit_code == 0 ]]; then
			echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] iptables_mangle module detected - enabling fwmark"
			# Use fwmark 1 to match old 03-network.sh exactly
			iptables -t mangle -A OUTPUT -p tcp --dport 8080 -j MARK --set-mark 1 -m comment --comment "Mark WebUI traffic for routing"
			iptables -t mangle -A OUTPUT -p tcp --sport 8080 -j MARK --set-mark 1 -m comment --comment "Mark WebUI traffic for routing"
		else
			echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] iptables_mangle module not available - skipping packet marking"
		fi
	fi
fi

# Route WebUI traffic over "$DEFAULT_IPV4_GATEWAY"
mkdir -p /etc/iproute2/
echo "8080 webui" >> /etc/iproute2/rt_tables

# Determine which fwmark to use based on legacy mode
if [[ "$LEGACY_IPTABLES" == "yes" ]] && [[ "$DSM_TEST_ENABLE_CONNTRACK" == "no" ]]; then
	# Legacy mode: use fwmark 1 like old 03-network.sh
	WEBUI_FWMARK=1
else
	# Modern mode: use fwmark 8080
	WEBUI_FWMARK=8080
fi

if [[ "$DSM_TEST_ENABLE_POLICY_ROUTING" == "yes" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] DSM_TEST_ENABLE_POLICY_ROUTING=yes - Using advanced policy routing with fwmark $WEBUI_FWMARK"
	if [ -n "$DEFAULT_IPV4_GATEWAY" ]; then
		# Default
		ip rule add fwmark $WEBUI_FWMARK table webui 
		ip route add default via "$DEFAULT_IPV4_GATEWAY" table webui
		# Look for local networks first
		ip rule add fwmark $WEBUI_FWMARK table main suppress_prefixlength 1
	fi
	if [ -n "$DEFAULT_IPV6_GATEWAY" ] && [[ "$DSM_TEST_ENABLE_IPV6" == "yes" ]]; then
		# Default
		ip -6 rule add fwmark $WEBUI_FWMARK table webui 
		ip -6 route add default via "$DEFAULT_IPV6_GATEWAY" table webui
		# Look for local networks first
		ip -6 rule add fwmark $WEBUI_FWMARK table main suppress_prefixlength 1
	fi
else
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] DSM_TEST_ENABLE_POLICY_ROUTING=no - Using simple routing (legacy mode) with fwmark $WEBUI_FWMARK"
	if [ -n "$DEFAULT_IPV4_GATEWAY" ]; then
		# Simple routing like old 03-network.sh
		ip rule add fwmark $WEBUI_FWMARK table webui 
		ip route add default via "$DEFAULT_IPV4_GATEWAY" table webui
		# Skip the suppress_prefixlength feature for legacy compatibility
	fi
	
	# Add legacy LAN network routing if LAN_NETWORK is set (like old 03-network.sh)
	if [[ -n "$LAN_NETWORK" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Adding legacy LAN network routing for: $LAN_NETWORK"
		# Split comma separated string into list from LAN_NETWORK env variable
		IFS=',' read -ra lan_network_list <<< "$LAN_NETWORK"
		
		# Process lan networks in the list
		for lan_network_item in "${lan_network_list[@]}"; do
			# Strip whitespace from start and end of lan_network_item
			lan_network_item=$(echo "$lan_network_item" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
			
			echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Adding $lan_network_item as route via docker $DOCKER_INTERFACE" 
			ip route add "$lan_network_item" via "$DEFAULT_IPV4_GATEWAY" dev "$DOCKER_INTERFACE" &> /dev/null
			
			ip_route_add_exit_code=$?
			if [[ $ip_route_add_exit_code != 0 ]]; then
				echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] Error adding route for $lan_network_item"
			fi
		done
	fi
fi

if [[ "$LEGACY_IPTABLES" != "yes" ]]; then
	# Add firewall table
	nft add table inet firewall

	# Create the sets for storing the IPv4 and IPv6 addresses
	nft "add set inet firewall vpn_ipv4 { type ipv4_addr ; }"
	nft "add set inet firewall vpn_ipv6 { type ipv6_addr ; }"
else
	# Test if we should use ipset or fall back to direct IP matching
	if [[ "$DSM_TEST_ENABLE_IPSET" == "yes" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] DSM_TEST_ENABLE_IPSET=yes - Using ipset module"
		# Create IP sets for IPv4 and IPv6 addresses
		ipset create vpn_ipv4 hash:ip family inet
		if [[ "$DSM_TEST_ENABLE_IPV6" == "yes" ]]; then
			ipset create vpn_ipv6 hash:ip family inet6
		fi
	else
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] DSM_TEST_ENABLE_IPSET=no - Using direct IP matching (legacy mode)"
		# Will use direct IP matching in iptables rules later
	fi
	
	# Check if xt_comment module is available (like old 03-network.sh)
	lsmod | grep xt_comment &> /dev/null
	xt_comment_exit_code=$?
	
	# Function to add iptables rules with conditional comment support
	function add_comment_rule() {
		local rule="$1"
		if [[ "$xt_comment_exit_code" -eq 0 ]]; then
			eval "$rule"
		else
			# Remove the comment part of the rule
			local no_comment_rule=$(echo "$rule" | sed -E "s/-m comment --comment \\\"[^\"]+\\\"//" | tr -d '\n')
			eval "$no_comment_rule"
		fi
	}
fi

## VPN_REMOTE IP

VPN_REMOTE_IPv4_ADDRESSES=()
VPN_REMOTE_IPv6_ADDRESSES=()

# VPN_REMOTE is already an IPv4 address
if (ipcalc -c -4 "$VPN_REMOTE" > /dev/null 2>&1); then
	VPN_REMOTE_IPv4_ADDRESSES+=("$VPN_REMOTE")
# VPN_REMOTE is already an IPv6 address
elif (ipcalc -c -6 "$VPN_REMOTE" > /dev/null 2>&1); then
	VPN_REMOTE_IPv6_ADDRESSES+=("$VPN_REMOTE")
# VPN_REMOTE is a hostname
else
	if [[ "${VPN_TYPE}" == "openvpn" ]]; then
		while ! VPN_REMOTE_IP=$(grep -o -m 1 -P 'Peer Connection Initiated with [^\d]+\K(\d+(\.\d+){3})(?=:\d+)' < /var/log/openvpn.log); do sleep 0.1; done
	else
		VPN_REMOTE_IP="$(wg show | grep -o -m 1 -P '((?<=endpoint:\s\[)[0-9a-f:]+(?=\]:\d+$))|((?<=endpoint:\s)[0-9.]+(?=:\d+$))')"
	fi

	if (ipcalc -c -4 "$VPN_REMOTE_IP" > /dev/null 2>&1); then
		VPN_REMOTE_IPv4_ADDRESSES+=("$VPN_REMOTE_IP")
	elif (ipcalc -c -6 "$VPN_REMOTE_IP" > /dev/null 2>&1); then
		VPN_REMOTE_IPv6_ADDRESSES+=("$VPN_REMOTE_IP")
	else
		echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] neither $VPN_REMOTE (VPN_REMOTE) nor \"$VPN_REMOTE_IP\" (obtained from the VPN client) is a valid IP"
		stop_container
	fi
fi

if [[ "$DEBUG" == "yes" ]]; then
	# shellcheck disable=SC2154
	echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] VPN_REMOTE_IPv4_ADDRESSES defined as (${VPN_REMOTE_IPv4_ADDRESSES[*]})"
	# shellcheck disable=SC2154
	echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] VPN_REMOTE_IPv6_ADDRESSES defined as (${VPN_REMOTE_IPv6_ADDRESSES[*]})"
fi

# Fill the sets with the VPN server addresses
if [[ "$LEGACY_IPTABLES" != "yes" ]]; then
	for address in "${VPN_REMOTE_IPv4_ADDRESSES[@]}"; do
		nft "add element inet firewall vpn_ipv4 { $address }"
	done
	for address in "${VPN_REMOTE_IPv6_ADDRESSES[@]}"; do
		nft "add element inet firewall vpn_ipv6 { $address }"
	done
else
	if [[ "$DSM_TEST_ENABLE_IPSET" == "yes" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Populating ipset with VPN server IPs"
		for address in "${VPN_REMOTE_IPv4_ADDRESSES[@]}"; do
			ipset add vpn_ipv4 "$address"
		done
		if [[ "$DSM_TEST_ENABLE_IPV6" == "yes" ]]; then
			for address in "${VPN_REMOTE_IPv6_ADDRESSES[@]}"; do
				ipset add vpn_ipv6 "$address"
			done
		fi
	else
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] VPN server IPs will be used directly in iptables rules"
		# Store the first IPv4 address for direct use (like old 03-network.sh)
		if [[ ${#VPN_REMOTE_IPv4_ADDRESSES[@]} -gt 0 ]]; then
			VPN_REMOTE_IP="${VPN_REMOTE_IPv4_ADDRESSES[0]}"
		elif [[ ${#VPN_REMOTE_IPv6_ADDRESSES[@]} -gt 0 ]] && [[ "$DSM_TEST_ENABLE_IPV6" == "yes" ]]; then
			VPN_REMOTE_IP="${VPN_REMOTE_IPv6_ADDRESSES[0]}"
		else
			echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] No usable VPN server IP found"
			stop_container
		fi
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Using VPN_REMOTE_IP: $VPN_REMOTE_IP"
	fi
fi

# Input
if [[ "$LEGACY_IPTABLES" != "yes" ]]; then
	nft "add chain inet firewall input { type filter hook input priority 0 ; policy drop ; }"
	
	nft "add rule inet firewall input iifname $VPN_DEVICE_TYPE accept comment \"Accept input from VPN tunnel\""
	nft "add rule inet firewall input $VPN_PROTOCOL sport $VPN_PORT ip saddr @vpn_ipv4 accept comment \"Accept input from VPN server \(IPv4\)\""
	nft "add rule inet firewall input $VPN_PROTOCOL sport $VPN_PORT ip6 saddr @vpn_ipv6 accept comment \"Accept input from VPN server \(IPv6\)\""
	nft "add rule inet firewall input iifname lo accept comment \"Accept input from internal loopback\""
	nft "add rule inet firewall input icmpv6 type {nd-neighbor-solicit,nd-neighbor-advert,nd-router-solicit,nd-router-advert} accept comment \"Basic ICMPv6 NDP\""
	nft "add rule inet firewall input icmpv6 type {destination-unreachable, packet-too-big, time-exceeded} accept comment \"Basic ICMPv6 errors (optional)\""
	nft "add rule inet firewall input icmp type {destination-unreachable, time-exceeded} accept comment \"Basic ICMP errors (optional)\""
	nft "add rule inet firewall input icmp type {echo-request} accept comment \"Respond to IPv4 pings (optional)\""
	nft "add rule inet firewall input icmpv6 type {echo-request} accept comment \"Respond to IPv6 pings (optional)\""
else
	iptables -P INPUT DROP
	if [[ "$DSM_TEST_ENABLE_IPV6" == "yes" ]]; then
		ip6tables -P INPUT DROP
	fi

	# Basic rules that should work on all systems
	add_comment_rule "iptables -A INPUT -i $VPN_DEVICE_TYPE -j ACCEPT -m comment --comment \"Accept input from VPN tunnel\""
	add_comment_rule "iptables -A INPUT -i lo -j ACCEPT -m comment --comment \"Accept input from internal loopback\""
	
	# Add Docker network rules if available (like old 03-network.sh)
	if [[ -n "$DOCKER_IPV4_NETWORK_CIDR" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Adding Docker network rules for $DOCKER_IPV4_NETWORK_CIDR"
		add_comment_rule "iptables -A INPUT -s $DOCKER_IPV4_NETWORK_CIDR -d $DOCKER_IPV4_NETWORK_CIDR -j ACCEPT -m comment --comment \"Accept input from internal Docker network\""
	fi
	
	# VPN server rules - use ipset or direct IP matching
	if [[ "$DSM_TEST_ENABLE_IPSET" == "yes" ]]; then
		add_comment_rule "iptables -A INPUT -p $VPN_PROTOCOL --sport $VPN_PORT -m set --match-set vpn_ipv4 src -j ACCEPT -m comment --comment \"Accept input from VPN server (IPv4)\""
		if [[ "$DSM_TEST_ENABLE_IPV6" == "yes" ]]; then
			add_comment_rule "ip6tables -A INPUT -p $VPN_PROTOCOL --sport $VPN_PORT -m set --match-set vpn_ipv6 src -j ACCEPT -m comment --comment \"Accept input from VPN server (IPv6)\""
		fi
	else
		# Legacy mode: direct IP matching like old 03-network.sh
		add_comment_rule "iptables -A INPUT -p $VPN_PROTOCOL --sport $VPN_PORT -s $VPN_REMOTE_IP -j ACCEPT -m comment --comment \"Accept input from VPN server\""
	fi

	# Advanced ICMP rules only if enabled
	if [[ "$DSM_TEST_ENABLE_ICMP_RULES" == "yes" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] DSM_TEST_ENABLE_ICMP_RULES=yes - Adding advanced ICMP rules"
		if [[ "$DSM_TEST_ENABLE_IPV6" == "yes" ]]; then
			add_comment_rule "ip6tables -A INPUT -p icmpv6 --icmpv6-type 135 -j ACCEPT -m comment --comment \"Basic ICMPv6 NDP (Neighbor Solicitation)\""
			add_comment_rule "ip6tables -A INPUT -p icmpv6 --icmpv6-type 136 -j ACCEPT -m comment --comment \"Basic ICMPv6 NDP (Neighbor Advertisement)\""
			add_comment_rule "ip6tables -A INPUT -p icmpv6 --icmpv6-type 133 -j ACCEPT -m comment --comment \"Basic ICMPv6 NDP (Router Solicitation)\""
			add_comment_rule "ip6tables -A INPUT -p icmpv6 --icmpv6-type 134 -j ACCEPT -m comment --comment \"Basic ICMPv6 NDP (Router Advertisement)\""
			add_comment_rule "ip6tables -A INPUT -p icmpv6 --icmpv6-type 1 -j ACCEPT -m comment --comment \"Basic ICMPv6 errors (Destination Unreachable)\""
			add_comment_rule "ip6tables -A INPUT -p icmpv6 --icmpv6-type 2 -j ACCEPT -m comment --comment \"Basic ICMPv6 errors (Packet Too Big)\""
			add_comment_rule "ip6tables -A INPUT -p icmpv6 --icmpv6-type 3 -j ACCEPT -m comment --comment \"Basic ICMPv6 errors (Time Exceeded)\""
			add_comment_rule "ip6tables -A INPUT -p icmpv6 --icmpv6-type 128 -j ACCEPT -m comment --comment \"Respond to IPv6 pings (Echo Request)\""
		fi
		add_comment_rule "iptables -A INPUT -p icmp --icmp-type destination-unreachable -j ACCEPT -m comment --comment \"Basic ICMP errors (optional)\""
		add_comment_rule "iptables -A INPUT -p icmp --icmp-type time-exceeded -j ACCEPT -m comment --comment \"Basic ICMP errors (optional)\""
		add_comment_rule "iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT -m comment --comment \"Respond to IPv4 pings (optional)\""
	else
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] DSM_TEST_ENABLE_ICMP_RULES=no - Skipping advanced ICMP rules"
	fi
fi


# Input to WebUI
if [ -z "$WEBUI_ALLOWED_NETWORKS" ]; then
	if [[ "$LEGACY_IPTABLES" != "yes" ]]; then
		nft "add rule inet firewall input tcp dport 8080 accept comment \"Accept input to the qBt WebUI\""
	else
		add_comment_rule "iptables -A INPUT -p tcp --dport 8080 -j ACCEPT -m comment --comment \"Accept input to the qBt WebUI\""
		if [[ "$DSM_TEST_ENABLE_IPV6" == "yes" ]]; then
			add_comment_rule "ip6tables -A INPUT -p tcp --dport 8080 -j ACCEPT -m comment --comment \"Accept input to the qBt WebUI\""
		fi
	fi
else
	# Create sets for storing the allowed IPv4 and IPv6 addresses
	if [[ "$LEGACY_IPTABLES" != "yes" ]]; then
		nft "add set inet firewall webui_allowed_networks_ipv4 { type ipv4_addr; flags interval ; }"
		nft "add set inet firewall webui_allowed_networks_ipv6 { type ipv6_addr; flags interval ; }"
	else
		if [[ "$DSM_TEST_ENABLE_IPSET" == "yes" ]]; then
			echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Creating ipset for WebUI allowed networks"
			ipset create webui_allowed_networks_ipv4 hash:net family inet
			if [[ "$DSM_TEST_ENABLE_IPV6" == "yes" ]]; then
				ipset create webui_allowed_networks_ipv6 hash:net family inet6
			fi
		else
			echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Will use direct network matching for WebUI access control"
		fi
	fi

	# Split comma separated string into list from WEBUI_ALLOWED_NETWORKS env variable
	IFS=',' read -ra allowed_networks_array <<< "$WEBUI_ALLOWED_NETWORKS"

	# Fill the sets with the allowed addresses
	for address in "${allowed_networks_array[@]}"; do
		# Remove whitepaces (for ipcalc)
		address="$(sed -e 's/\s//g' <<< "$address")"

		if ipcalc -c -4 "$address"; then
			if [[ "$LEGACY_IPTABLES" != "yes" ]]; then
				nft "add element inet firewall webui_allowed_networks_ipv4 { $address }"
			else
				if [[ "$DSM_TEST_ENABLE_IPSET" == "yes" ]]; then
					ipset add webui_allowed_networks_ipv4 "$address"
				else
					# For legacy mode without ipset, add individual rules
					add_comment_rule "iptables -A INPUT -p tcp --dport 8080 -s $address -j ACCEPT -m comment --comment \"Accept input to the qBt WebUI from $address\""
				fi
			fi
		elif ipcalc -c -6 "$address" && [[ "$DSM_TEST_ENABLE_IPV6" == "yes" ]]; then
			if [[ "$LEGACY_IPTABLES" != "yes" ]]; then
				nft "add element inet firewall webui_allowed_networks_ipv6 { $address }"
			else
				if [[ "$DSM_TEST_ENABLE_IPSET" == "yes" ]]; then
					ipset add webui_allowed_networks_ipv6 "$address"
				else
					# For legacy mode without ipset, add individual rules
					add_comment_rule "ip6tables -A INPUT -p tcp --dport 8080 -s $address -j ACCEPT -m comment --comment \"Accept input to the qBt WebUI from $address\""
				fi
			fi
		fi
	done

	# Add rules to accept incoming connections to the WebUI from the allowed networks
	if [[ "$LEGACY_IPTABLES" != "yes" ]]; then
		nft "add rule inet firewall input tcp dport 8080 ip saddr @webui_allowed_networks_ipv4 counter accept comment \"Accept input to the qBt WebUI \(IPv4\)\""
		nft "add rule inet firewall input tcp dport 8080 ip6 saddr @webui_allowed_networks_ipv6 counter accept comment \"Accept input to the qBt WebUI \(IPv6\)\""
	else
		if [[ "$DSM_TEST_ENABLE_IPSET" == "yes" ]]; then
			add_comment_rule "iptables -A INPUT -p tcp --dport 8080 -m set --match-set webui_allowed_networks_ipv4 src -j ACCEPT -m comment --comment \"Accept input to the qBt WebUI (IPv4)\""
			if [[ "$DSM_TEST_ENABLE_IPV6" == "yes" ]]; then
				add_comment_rule "ip6tables -A INPUT -p tcp --dport 8080 -m set --match-set webui_allowed_networks_ipv6 src -j ACCEPT -m comment --comment \"Accept input to the qBt WebUI (IPv6)\""
			fi
		fi
		# Note: Individual rules were already added in the loop above for legacy mode
	fi
fi

# Output
if [[ "$LEGACY_IPTABLES" != "yes" ]]; then
	nft "add chain inet firewall output { type filter hook postrouting priority 0 ; policy drop ; }"

	nft "add rule inet firewall output oifname $VPN_DEVICE_TYPE accept comment \"Accept output to VPN tunnel\""
	nft "add rule inet firewall output $VPN_PROTOCOL dport $VPN_PORT ip daddr @vpn_ipv4 accept comment \"Accept output to VPN server \(IPv4\)\""
	nft "add rule inet firewall output $VPN_PROTOCOL dport $VPN_PORT ip6 daddr @vpn_ipv6 accept comment \"Accept output to VPN server \(IPv6\)\""
	nft "add rule inet firewall output tcp sport 8080 meta mark 8080 counter accept comment \"Accept outgoing packets belonging to a WebUI connection\""
	nft "add rule inet firewall output iifname lo accept comment \"Accept output to internal loopback\""
	nft "add rule inet firewall output icmpv6 type {nd-neighbor-solicit,nd-neighbor-advert,nd-router-solicit,nd-router-advert} accept comment \"Basic ICMPv6 NDP\""
	nft "add rule inet firewall output icmpv6 type {destination-unreachable, packet-too-big, time-exceeded} accept comment \"ICMPv6 errors (optional)\""
	nft "add rule inet firewall output icmp type {destination-unreachable, time-exceeded} accept comment \"ICMP errors (optional)\""
	nft "add rule inet firewall output icmp type {echo-reply} accept comment \"Respond to IPv4 pings (optional)\""
	nft "add rule inet firewall output icmpv6 type {echo-reply} accept comment \"Respond to IPv6 pings (optional)\""

else
	iptables -P OUTPUT DROP
	if [[ "$DSM_TEST_ENABLE_IPV6" == "yes" ]]; then
		ip6tables -P OUTPUT DROP
	fi

	# Basic rules that should work on all systems
	add_comment_rule "iptables -A OUTPUT -o $VPN_DEVICE_TYPE -j ACCEPT -m comment --comment \"Accept output to VPN tunnel\""
	add_comment_rule "iptables -A OUTPUT -o lo -j ACCEPT -m comment --comment \"Accept output to internal loopback\""
	
	# Add Docker network rules if available (like old 03-network.sh)
	if [[ -n "$DOCKER_NETWORK_CIDR" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Adding Docker network output rules for $DOCKER_NETWORK_CIDR"
		add_comment_rule "iptables -A OUTPUT -s $DOCKER_NETWORK_CIDR -d $DOCKER_NETWORK_CIDR -j ACCEPT -m comment --comment \"Accept output to internal Docker network\""
	fi
	
	# VPN server rules - use ipset or direct IP matching
	if [[ "$DSM_TEST_ENABLE_IPSET" == "yes" ]]; then
		add_comment_rule "iptables -A OUTPUT -p $VPN_PROTOCOL --dport $VPN_PORT -m set --match-set vpn_ipv4 dst -j ACCEPT -m comment --comment \"Accept output to VPN server (IPv4)\""
		if [[ "$DSM_TEST_ENABLE_IPV6" == "yes" ]]; then
			add_comment_rule "ip6tables -A OUTPUT -p $VPN_PROTOCOL --dport $VPN_PORT -m set --match-set vpn_ipv6 dst -j ACCEPT -m comment --comment \"Accept output to VPN server (IPv6)\""
		fi
	else
		# Legacy mode: direct IP matching like old 03-network.sh
		add_comment_rule "iptables -A OUTPUT -p $VPN_PROTOCOL --dport $VPN_PORT -d $VPN_REMOTE_IP -j ACCEPT -m comment --comment \"Accept output to VPN server\""
	fi

	# WebUI traffic - use mark matching or simple interface matching
	if [[ "$DSM_TEST_ENABLE_MARK_MATCHING" == "yes" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] DSM_TEST_ENABLE_MARK_MATCHING=yes - Using mark-based WebUI output rules with fwmark $WEBUI_FWMARK"
		add_comment_rule "iptables -A OUTPUT -p tcp --sport 8080 -m mark --mark $WEBUI_FWMARK -j ACCEPT -m comment --comment \"Accept outgoing packets belonging to a WebUI connection\""
	else
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] DSM_TEST_ENABLE_MARK_MATCHING=no - Using simple interface-based WebUI output rules"
		# Legacy mode: simple interface-based rule like old 03-network.sh
		add_comment_rule "iptables -A OUTPUT -p tcp --sport 8080 -j ACCEPT -m comment --comment \"Accept output from qBittorrent webui port\""
	fi

	# Advanced ICMP rules only if enabled
	if [[ "$DSM_TEST_ENABLE_ICMP_RULES" == "yes" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] DSM_TEST_ENABLE_ICMP_RULES=yes - Adding advanced ICMP output rules"
		if [[ "$DSM_TEST_ENABLE_IPV6" == "yes" ]]; then
			add_comment_rule "ip6tables -A OUTPUT -p icmpv6 --icmpv6-type 135 -j ACCEPT -m comment --comment \"Basic ICMPv6 NDP (Neighbor Solicitation)\""
			add_comment_rule "ip6tables -A OUTPUT -p icmpv6 --icmpv6-type 136 -j ACCEPT -m comment --comment \"Basic ICMPv6 NDP (Neighbor Advertisement)\""
			add_comment_rule "ip6tables -A OUTPUT -p icmpv6 --icmpv6-type 133 -j ACCEPT -m comment --comment \"Basic ICMPv6 NDP (Router Solicitation)\""
			add_comment_rule "ip6tables -A OUTPUT -p icmpv6 --icmpv6-type 134 -j ACCEPT -m comment --comment \"Basic ICMPv6 NDP (Router Advertisement)\""
			add_comment_rule "ip6tables -A OUTPUT -p icmpv6 --icmpv6-type 1 -j ACCEPT -m comment --comment \"ICMPv6 errors (Destination Unreachable)\""
			add_comment_rule "ip6tables -A OUTPUT -p icmpv6 --icmpv6-type 2 -j ACCEPT -m comment --comment \"ICMPv6 errors (Packet Too Big)\""
			add_comment_rule "ip6tables -A OUTPUT -p icmpv6 --icmpv6-type 3 -j ACCEPT -m comment --comment \"ICMPv6 errors (Time Exceeded)\""
			add_comment_rule "ip6tables -A OUTPUT -p icmpv6 --icmpv6-type 129 -j ACCEPT -m comment --comment \"Respond to IPv6 pings (Echo Reply)\""
		fi
		add_comment_rule "iptables -A OUTPUT -p icmp --icmp-type destination-unreachable -j ACCEPT -m comment --comment \"ICMP errors (optional)\""
		add_comment_rule "iptables -A OUTPUT -p icmp --icmp-type time-exceeded -j ACCEPT -m comment --comment \"ICMP errors (optional)\""
		add_comment_rule "iptables -A OUTPUT -p icmp --icmp-type echo-reply -j ACCEPT -m comment --comment \"Respond to IPv4 pings (optional)\""
	else
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] DSM_TEST_ENABLE_ICMP_RULES=no - Skipping advanced ICMP output rules"
	fi
fi

# Additional port list for scripts or container linking
if [[ -n "$ADDITIONAL_PORTS" ]]; then
	IFS=',' read -ra additional_port_list <<< "$ADDITIONAL_PORTS"
	echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] ADDITIONAL_PORTS is deprecated."

	for additional_port_item in "${additional_port_list[@]}"; do
		additional_port_item=$(echo "$additional_port_item" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Adding additional incomming/outgoing port $additional_port_item for $DOCKER_INTERFACE"
		
		if [[ "$LEGACY_IPTABLES" != "yes" ]]; then
			nft "add rule inet firewall input tcp dport $additional_port_item accept comment \"Accept input from additional port\""
			nft "add rule inet firewall output oifname $DOCKER_INTERFACE tcp sport $additional_port_item accept comment \"Accept output to additional port\""
		else
			add_comment_rule "iptables -A INPUT -p tcp --dport $additional_port_item -j ACCEPT -m comment --comment \"Accept input from additional port\""
			add_comment_rule "iptables -A OUTPUT -o $DOCKER_INTERFACE -p tcp --sport $additional_port_item -j ACCEPT -m comment --comment \"Accept output to additional port\""
		fi
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

	if [[ "$LEGACY_IPTABLES" != "yes" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] nft ruleset defined as follows..."
		echo "--------------------"
		nft list ruleset
		echo "--------------------"
	else
		echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] iptables rules defined as follows..."
		echo "--------------------"
		iptables -S
		echo "--------------------"
		echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] ip6tables rules defined as follows..."
		echo "--------------------"
		ip6tables -S
		echo "--------------------"
	fi

    test_connection
fi

##########
# Save envirnonment variables

CONT_INIT_ENV="/var/run/s6/container_environment"
mkdir -p $CONT_INIT_ENV
export_vars=("DOCKER_INTERFACE")

for name in "${export_vars[@]}"; do
	echo -n "${!name}" > "$CONT_INIT_ENV/$name"
done
