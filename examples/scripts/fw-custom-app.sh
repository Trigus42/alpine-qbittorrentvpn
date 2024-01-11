#!/usr/bin/with-contenv bash
# shellcheck shell=bash

# Required tools
tools=( "bash" "nftables" )

# Incomming port to whitelist
port=9238

# Those vars can be different from each other/the port
# They have to be unique in your container
ct_mark=9238
meta_mark=9238
routing_table_number=9238
routing_table_name="my-app"
table_name="my-app-mark"

# Install requirements
apk add "${tools[@]}" > /dev/null

# Get default gateways and interface
# Works before and after VPN start
docker_ipv4_gateway=$(ip -4 route list 0/0 | cut -d ' ' -f 3 | head -n 1)
docker_ipv6_gateway=$(ip -6 route list ::0/0 | cut -d ' ' -f 3 | head -n 1)
docker_interface=$(ip -4 route list 0/0 | cut -d ' ' -f 5 | head -n 1)

# Mark outgoing packets belonging to the custom application
nft "add table inet $table_name"
nft "add chain inet $table_name prerouting { type filter hook prerouting priority -150 ; }"
nft "add chain inet $table_name output { type route hook output priority -150 ; }"
nft "add rule inet $table_name prerouting iif eth0 tcp dport $port ct state new ct mark set $ct_mark counter"
nft "add rule inet $table_name output ct mark $ct_mark meta mark set $meta_mark counter"

# Route application traffic over default gateway (instead of VPN)
echo "$routing_table_number $routing_table_name" >> /etc/iproute2/rt_tables
if [ -n "$docker_ipv4_gateway" ]; then
	ip rule add fwmark $meta_mark table $routing_table_name
	ip route add default via "$docker_ipv4_gateway" table $routing_table_name
fi
if [ -n "$docker_ipv6_gateway" ]; then
	ip -6 rule add fwmark $meta_mark table $routing_table_name
	ip -6 route add default via "$docker_ipv6_gateway" eth0 table $routing_table_name
fi

# Allow traffic of custom application
nft add table inet firewall
nft "add rule inet firewall input iifname $docker_interface tcp dport $port counter accept"
nft "add rule inet firewall output oifname $docker_interface tcp sport $port meta mark $meta_mark counter accept"