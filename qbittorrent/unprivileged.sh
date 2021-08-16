#!/bin/bash

if [[ "${VPN_TYPE}" == "wireguard" ]]; then
    # Check if net.ipv4.conf.all.src_valid_mark is set to 1
    if [ "$(sysctl net.ipv4.conf.all.src_valid_mark)" == "net.ipv4.conf.all.src_valid_mark = 1" ]; then
        # Update sed
        apk add --no-cache --quiet sed
        # Modify wg-quick to run in unprivileged container
        sed -i -E 's/&& cmd sysctl -q net.ipv4.conf.all.src_valid_mark=1//gm' "$(command -v wg-quick)"
    else
        echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] Trying to run in unprivileged mode but $(sysctl net.ipv4.conf.all.src_valid_mark)"
        sleep 10
        exit 1
    fi
fi