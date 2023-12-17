#!/usr/bin/with-contenv bash
# shellcheck shell=bash

# Incomming port to whitelist
PORT=9238

# Those vars can be different from each other/the port
# They have to be unique in your container
CT_MARK=9238
META_MARK=9238
ROUTING_TABLE_NUMBER=9238
ROUTING_TABLE_NAME="my-app"
TABLE_NAME="my-app-mark"

# Mark outgoing packets belonging to the custom application
nft "add table inet $TABLE_NAME"
nft "add chain inet $TABLE_NAME prerouting { type filter hook prerouting priority -150 ; }"
nft "add chain inet $TABLE_NAME output { type route hook output priority -150 ; }"
nft "add rule inet $TABLE_NAME prerouting iif eth0 tcp dport $PORT ct state new ct mark set $CT_MARK counter"
nft "add rule inet $TABLE_NAME output ct mark $CT_MARK meta mark set $META_MARK counter comment"

# Route application traffic over default gateway (instead of VPN)
echo "$ROUTING_TABLE_NUMBER $ROUTING_TABLE_NAME" >> /etc/iproute2/rt_tables
if [ -n "$DEFAULT_IPV4_GATEWAY" ]; then
	ip rule add fwmark $META_MARK table $ROUTING_TABLE_NAME
	ip route add default via "$DEFAULT_IPV4_GATEWAY" table $ROUTING_TABLE_NAME
fi
if [ -n "$DEFAULT_IPV6_GATEWAY" ]; then
	ip -6 rule add fwmark $META_MARK table $ROUTING_TABLE_NAME
	ip -6 route add default via "$DEFAULT_IPV6_GATEWAY" eth0 table $ROUTING_TABLE_NAME
fi

# Allow traffic of custom application
nft add table inet firewall
nft "add rule inet firewall input iifname $DOCKER_INTERFACE tcp dport $PORT counter accept"
nft "add rule inet firewall output oifname $DOCKER_INTERFACE tcp sport $PORT meta mark $META_MARK counter accept"