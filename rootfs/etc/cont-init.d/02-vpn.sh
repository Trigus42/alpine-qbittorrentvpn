#!/usr/bin/with-contenv bash
# shellcheck shell=bash

##########
# Skip if VPN is disabled

if [[ $VPN_ENABLED == "no" ]]; then
    exit 0
fi

##########
# Check for config file

# Create config dir (if it doesn't exist)
mkdir -p "/config/${VPN_TYPE}"

# Wildcard search for openvpn config files and store results in array
if [[ "${VPN_TYPE}" == "openvpn" ]]; then
    mapfile -t VPN_CONFIGS < <( find /config/openvpn -maxdepth 1 -name "*.ovpn" -print )
else
    mapfile -t VPN_CONFIGS < <( find /config/wireguard -maxdepth 1 -name "*.conf" -print )
fi

# Choose random config
VPN_CONFIG="${VPN_CONFIGS[$RANDOM % ${#VPN_CONFIGS[@]}]}"

# Get the VPN_CONFIG name without the path and extension
VPN_CONFIG_BASENAME="${VPN_CONFIG##*/}"
VPN_CONFIG_NAME="${VPN_CONFIG_BASENAME%.*}"

echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Choosen VPN config: '${VPN_CONFIG_BASENAME}'"

export VPN_CONFIG
export VPN_CONFIG_NAME

# If VPN config file not found in /config/openvpn or /config/wireguard then exit
if [[ -z ${VPN_CONFIG} ]]; then
    if [[ ${VPN_TYPE} == "openvpn" ]]; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] No OpenVPN config file found in /config/openvpn/. Please download one from your VPN provider and restart this container. Make sure the file extension is '.ovpn'"
    else
        echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] No WireGuard config file found in /config/wireguard/. Please download one from your VPN provider and restart this container. Make sure the file extension is '.conf'"
    fi
    # Sleep so it wont 'spam restart'
    sleep 5
    exit 1
fi

##########
# OpenVPN credentails

if [[ "${VPN_TYPE}" == "openvpn" ]]; then
    # Remove auth-user-pass line(s) from VPN config
    sed -i -E 's/auth-user-pass.*//g' "${VPN_CONFIG}"
    # Use credentials from credentials file if it exists
    if [[ -f /config/openvpn/"${VPN_CONFIG_NAME}"_credentials.conf ]]; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Using credentials from /config/openvpn/${VPN_CONFIG_NAME}_credentials.conf"
    # Else use credentials from env vars if set and non empty
    elif [[ -n "${VPN_USERNAME}" ]] && [[ -n "${VPN_PASSWORD}" ]]; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Copying credentials from env vars to /config/openvpn/${VPN_CONFIG_NAME}_credentials.conf"
        echo "${VPN_USERNAME}" > /config/openvpn/"${VPN_CONFIG_NAME}"_credentials.conf
        echo "${VPN_PASSWORD}" >> /config/openvpn/"${VPN_CONFIG_NAME}"_credentials.conf
    # Else if both username and password are set but empty, assume custom authentication method
    elif [[ -z "${VPN_USERNAME-unset}" ]] && [[ -z "${VPN_PASSWORD-unset}" ]]; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Credentials explicitly set to empty string"
    # Else if a credentials.conf file exists, assume it is valid for all VPN configs
    elif [[ -f /config/openvpn/credentials.conf ]]; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Copying credentials from /config/openvpn/credentials.conf to /config/openvpn/${VPN_CONFIG_NAME}_credentials.conf"
        cp /config/openvpn/credentials.conf /config/openvpn/"${VPN_CONFIG_NAME}"_credentials.conf
    else
        echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] No credentials set and didn't find a credential config file."
        # Sleep so it wont 'spam restart'
        sleep 5
        exit 1
    fi
fi

##########
# Read VPN config

# Convert CRLF (windows) to LF (unix)
dos2unix "${VPN_CONFIG}" 1> /dev/null

# Parse values from the ovpn or conf file
if [[ "${VPN_TYPE}" == "openvpn" ]]; then
    export vpn_remote_line=$( (grep -P -o -m 1 '(?<=^remote\s)[^\n\r]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~') < "${VPN_CONFIG}")
else
    export vpn_remote_line=$( (grep -P -o -m 1 '(?<=^Endpoint)(\s{0,})[^\n\r]+' | sed -e 's~^[=\ ]*~~') < "${VPN_CONFIG}")
fi

if [[ -n "${vpn_remote_line}" ]]; then
    echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] VPN remote line defined as '${vpn_remote_line}'"
else
    echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] VPN configuration file ${VPN_CONFIG} does not contain 'remote' line, showing contents of file before exit..."
    cat "${VPN_CONFIG}"
    # Sleep so it wont 'spam restart'
    sleep 5
    exit 1
fi

if [[ "${VPN_TYPE}" == "openvpn" ]]; then
    export VPN_REMOTE=$(echo "${vpn_remote_line}" | grep -P -o -m 1 '^[^\s\r\n]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
else
    export VPN_REMOTE=$(echo "${vpn_remote_line}" | grep -P -o -m 1 '^[^:\r\n]+')
fi

if [[ -n "${VPN_REMOTE}" ]]; then
    echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] VPN_REMOTE defined as '${VPN_REMOTE}'"
else
    echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] VPN_REMOTE not found in ${VPN_CONFIG}, exiting..."
    # Sleep so it wont 'spam restart'
    sleep 5
    exit 1
fi

if [[ "${VPN_TYPE}" == "openvpn" ]]; then
    export VPN_PORT=$(echo "${vpn_remote_line}" | grep -P -o -m 1 '(?<=\s)\d{2,5}(?=\s)?+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
else
    export VPN_PORT=$(echo "${vpn_remote_line}" | grep -P -o -m 1 '(?<=:)\d{2,5}(?=:)?+')
fi

if [[ -n "${VPN_PORT}" ]]; then
    echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] VPN_PORT defined as '${VPN_PORT}'"
else
    echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] VPN_PORT not found in ${VPN_CONFIG}, exiting..."
    # Sleep so it wont 'spam restart'
    sleep 5
    exit 1
fi

if [[ "${VPN_TYPE}" == "openvpn" ]]; then
    export VPN_PROTOCOL=$( (grep -P -o -m 1 '(?<=^proto\s)[^\r\n]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~') < "${VPN_CONFIG}")
    if [[ -n "${VPN_PROTOCOL}" ]]; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] VPN_PROTOCOL defined as '${VPN_PROTOCOL}'"
    else
        export VPN_PROTOCOL=$(echo "${vpn_remote_line}" | grep -P -o -m 1 'udp|tcp-client|tcp$' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
        if [[ -n "${VPN_PROTOCOL}" ]]; then
            echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] VPN_PROTOCOL defined as '${VPN_PROTOCOL}'"
        else
            echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] VPN_PROTOCOL not found in ${VPN_CONFIG}, assuming udp"
            export VPN_PROTOCOL="udp"
        fi
    fi
    # Required for use in iptables
    if [[ "${VPN_PROTOCOL}" == "tcp-client" ]]; then
        export VPN_PROTOCOL="tcp"
    fi
else
    export VPN_PROTOCOL="udp"
    echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] VPN_PROTOCOL set as '${VPN_PROTOCOL}', since WireGuard is always ${VPN_PROTOCOL}."
fi


if [[ "${VPN_TYPE}" == "openvpn" ]]; then
    VPN_DEVICE_TYPE=$( awk '/dev/ {print $2}' < "${VPN_CONFIG}")
    if [[ -n "${VPN_DEVICE_TYPE}" ]]; then
        export VPN_DEVICE_TYPE="${VPN_DEVICE_TYPE}0"
        echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] VPN_DEVICE_TYPE defined as '${VPN_DEVICE_TYPE}'"
    else
        echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] VPN_DEVICE_TYPE not found in ${VPN_CONFIG}, exiting..."
        # Sleep so it wont 'spam restart'
        sleep 5
        exit 1
    fi
else
    export VPN_DEVICE_TYPE="$VPN_CONFIG_NAME"
    echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] VPN_DEVICE_TYPE set as '${VPN_DEVICE_TYPE}'"
fi

##########
# Unprivileged mode

if [[ "${VPN_TYPE}" == "wireguard" ]]; then
    # Check if net.ipv4.conf.all.src_valid_mark can be set (container running in privileged mode)
    if ! (sysctl -q net.ipv4.conf.all.src_valid_mark=1 >/dev/null 2>&1); then
        # Check if net.ipv4.conf.all.src_valid_mark is already set to 1
        if [ "$(sysctl net.ipv4.conf.all.src_valid_mark)" == "net.ipv4.conf.all.src_valid_mark = 1" ]; then
            # Modify wg-quick to run in unprivileged container
            sed -i -E 's/&& cmd sysctl -q net.ipv4.conf.all.src_valid_mark=1//gm' "$(command -v wg-quick)"
        else
            echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] Trying to run in unprivileged mode but $(sysctl net.ipv4.conf.all.src_valid_mark)"
            sleep 5
            exit 1
        fi
    fi
fi

# Exit if any of the following commands fails
set -e

if [[ $VPN_ENABLED == "yes" ]]; then
	if [[ "${VPN_TYPE}" == "openvpn" ]]; then
		# Char device is only created in privileged mode; If only cap-add=NET_ADMIN is set we have to create it manually
		mkdir -p /dev/net
		if [ ! -c /dev/net/tun ]; then
			mknod /dev/net/tun c 10 200
		fi

        echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Starting OpenVPN..."
        echo "--------------------"

        # Check if credential file exists and is not empty
        if [[ -s /config/openvpn/"${VPN_CONFIG_NAME}"_credentials.conf ]]; then
            openvpn --pull-filter ignore "route-ipv6" --pull-filter ignore "ifconfig-ipv6" --pull-filter ignore "tun-ipv6" --pull-filter ignore "redirect-gateway ipv6" --pull-filter ignore "dhcp-option DNS6" --auth-user-pass /config/openvpn/"${VPN_CONFIG_NAME}"_credentials.conf --config "${VPN_CONFIG}" --script-security 2 --up /helper/resume-after-connect &
        else
            openvpn --pull-filter ignore "route-ipv6" --pull-filter ignore "ifconfig-ipv6" --pull-filter ignore "tun-ipv6" --pull-filter ignore "redirect-gateway ipv6" --pull-filter ignore "dhcp-option DNS6" --config "${VPN_CONFIG}" --script-security 2 --up /helper/resume-after-connect &
        fi

        # Capture the PID of the background OpenVPN process
        openvpn_pid=$!

        if [[ "$DEBUG" == "yes" ]]; then
            echo "$(date +'%Y-%m-%d %H:%M:%S') [DEBUG] OpenVPN PID: $openvpn_pid"
        fi

        # Wait for startup
        while :; do
            # Process exited
            if ! ps -p $openvpn_pid > /dev/null; then
                echo "--------------------"
                echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] Failed to start OpenVPN"
                exit 1
            # Startup was successfull
            elif [[ -f /tmp/openvpn_startup_finished ]]; then
                break
            fi
            sleep 0.1
        done
        echo "--------------------"

	else
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Starting WireGuard..."
		echo "--------------------"
		wg-quick up "$VPN_CONFIG"
		echo "--------------------"
	fi
fi

set +e

##########
# Save envirnonment variables

CONT_INIT_ENV="/var/run/s6/container_environment"
mkdir -p $CONT_INIT_ENV
export_vars=("VPN_REMOTE" "VPN_PORT" "VPN_PROTOCOL" "VPN_DEVICE_TYPE" "VPN_CONFIG_NAME")

for name in "${export_vars[@]}"; do
	echo -n "${!name}" > "$CONT_INIT_ENV/$name"
done
