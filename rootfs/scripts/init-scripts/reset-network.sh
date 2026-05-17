#!/bin/bash

# shellcheck disable=SC1091
source /scripts/helper/functions.sh
##########
# Skip if VPN is disabled

if [[ $VPN_ENABLED == "no" ]]; then
    exit 0
fi

echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Ensuring clean network state..."

##########
# Tear down stale WireGuard interfaces
for wg_iface in $(ip -o link show type wireguard 2>/dev/null | awk -F': ' '{print $2}'); do
    echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Removing stale WireGuard interface: $wg_iface"
    ip link delete "$wg_iface" 2>/dev/null
done

##########
# Flush our nftables tables (leaves any user-created tables intact)

nft delete table inet qbt-mark 2>/dev/null
nft delete table inet qbt-firewall 2>/dev/null

##########
# Remove our ip rules and routing table

# Remove all fwmark 8080 rules (may exist multiple times)
while ip rule del fwmark 8080 2>/dev/null; do :; done
while ip -6 rule del fwmark 8080 2>/dev/null; do :; done

# Flush the webui routing table (if it exists)
ip route flush table webui 2>/dev/null
ip -6 route flush table webui 2>/dev/null

# Remove our entry from rt_tables (leave the file intact otherwise)
sed -i '/^8080[[:space:]]\+webui$/d' /etc/iproute2/rt_tables 2>/dev/null

echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Network state reset complete"
