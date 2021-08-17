#!/bin/bash
set -e

# Check for presence of network interface docker0
check_network=$(ifconfig | grep docker0 || true)

# If network interface docker0 is present then we are running in host mode and thus must exit
if [[ -n "${check_network}" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] Network type detected as 'Host', this will cause major issues, please stop the container and switch back to 'Bridge' mode"
	# Sleep so it wont 'spam restart'
	sleep 10
	exit 1
fi

# PUID/PGID
if [[ -z "${PUID}" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] PUID not defined. Defaulting to 1001"
	export PUID="1001"
else
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] PUID defined as $PUID"
fi
if [[ -z "${PGID}" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] PGID not defined. Defaulting to 1001"
	export PGID="1001"
else
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] PGID defined as $PGID"
fi

# Unprivileged mode
if [ "${UNPRIVILEGED}" == "yes" ]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Unprivileged mode enabled"
	/bin/bash /init/unprivileged.sh
elif [ "${UNPRIVILEGED}" != "no" ]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Unprivileged not set or invalid value, defaulting to privileged mode."
	export UNPRIVILEGED=false
fi

export VPN_ENABLED=$(echo "${VPN_ENABLED,,}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ -n "${VPN_ENABLED}" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] VPN_ENABLED defined as '${VPN_ENABLED}'"
else
	echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] VPN_ENABLED not defined,(via -e VPN_ENABLED), defaulting to 'yes'"
	export VPN_ENABLED="yes"
fi

if [[ $VPN_ENABLED == "yes" ]]; then
	# Check if VPN_TYPE is set.
	if [[ -z "${VPN_TYPE}" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] VPN_TYPE not set, defaulting to Wireguard."
		export VPN_TYPE="wireguard"
	else
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] VPN_TYPE defined as '${VPN_TYPE}'"
	fi

	if [[ "${VPN_TYPE}" != "openvpn" && "${VPN_TYPE}" != "wireguard" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] VPN_TYPE not set, as 'wireguard' or 'openvpn', defaulting to Wireguard."
		export VPN_TYPE="wireguard"
	fi

	# Create the directory to store OpenVPN or WireGuard config files
	mkdir -p /config/${VPN_TYPE}
	# Set permmissions and owner for files in /config/openvpn or /config/wireguard directory
	set +e
	chown -R "${PUID}":"${PGID}" "/config/${VPN_TYPE}" &> /dev/null
	exit_code_chown=$?
	chmod -R 775 "/config/${VPN_TYPE}" &> /dev/null
	exit_code_chmod=$?
	set -e
	if (( $exit_code_chown != 0 || $exit_code_chmod != 0 )); then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] Unable to chown/chmod /config/${VPN_TYPE}/, assuming SMB mountpoint"
	fi

	# Wildcard search for openvpn config files (match on first result)
	if [[ "${VPN_TYPE}" == "openvpn" ]]; then
		export VPN_CONFIG=$(find /config/openvpn -maxdepth 1 -name "*.ovpn" -print -quit)
	else
		export VPN_CONFIG=$(find /config/wireguard -maxdepth 1 -name "*.conf" -print -quit)
	fi

	# If VPN config file not found in /config/openvpn or /config/wireguard then exit
	if [[ -z "${VPN_CONFIG}" ]]; then
		if [[ "${VPN_TYPE}" == "openvpn" ]]; then
			echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] No OpenVPN config file found in /config/openvpn/. Please download one from your VPN provider and restart this container. Make sure the file extension is '.ovpn'"
		else
			echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] No WireGuard config file found in /config/wireguard/. Please download one from your VPN provider and restart this container. Make sure the file extension is '.conf'"
		fi
		# Sleep so it wont 'spam restart'
		sleep 10
		exit 1
	fi

	if [[ "${VPN_TYPE}" == "openvpn" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] OpenVPN config file is found at ${VPN_CONFIG}"
	else
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] WireGuard config file is found at ${VPN_CONFIG}"
		if [[ "${VPN_CONFIG}" != "/config/wireguard/wg0.conf" ]]; then
			echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] WireGuard config filename is not 'wg0.conf'"
			echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] Rename ${VPN_CONFIG} to 'wg0.conf'"
			sleep 10
			exit 1
		fi
	fi

	# Read username and password env vars and put them in credentials.conf, then add ovpn config for credentials file
	if [[ "${VPN_TYPE}" == "openvpn" ]]; then
		# Replace line with one that points to credentials.conf
			auth_cred_exist=$(grep -m 1 'auth-user-pass' < "${VPN_CONFIG}")
			if [[ -n "${auth_cred_exist}" ]]; then
				# Get line number of auth-user-pass
				LINE_NUM=$(grep -Fn -m 1 'auth-user-pass' "${VPN_CONFIG}" | cut -d: -f 1)
				sed -i "${LINE_NUM}s/.*/auth-user-pass credentials.conf/" "${VPN_CONFIG}"
			else
				sed -i "1s/.*/auth-user-pass credentials.conf/" "${VPN_CONFIG}"
			fi

		if [[ -n "${VPN_USERNAME}" ]] && [[ -n "${VPN_PASSWORD}" ]]; then
			if [[ ! -e /config/openvpn/credentials.conf ]]; then
				touch /config/openvpn/credentials.conf
			fi
			echo "${VPN_USERNAME}" > /config/openvpn/credentials.conf
			echo "${VPN_PASSWORD}" >> /config/openvpn/credentials.conf
		fi
	fi
	
	# Convert CRLF (windows) to LF (unix) for ovpn
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
		sleep 10
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
		sleep 10
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
		sleep 10
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
		VPN_DEVICE_TYPE=$( (grep -P -o -m 1 '(?<=^dev\s)[^\r\n\d]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~') < "${VPN_CONFIG}")
		if [[ -n "${VPN_DEVICE_TYPE}" ]]; then
			export VPN_DEVICE_TYPE="${VPN_DEVICE_TYPE}0"
			echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] VPN_DEVICE_TYPE defined as '${VPN_DEVICE_TYPE}'"
		else
			echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] VPN_DEVICE_TYPE not found in ${VPN_CONFIG}, exiting..."
			# Sleep so it wont 'spam restart'
			sleep 10
			exit 1
		fi
	else
		export VPN_DEVICE_TYPE="wg0"
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] VPN_DEVICE_TYPE set as '${VPN_DEVICE_TYPE}', since WireGuard will always be wg0."
	fi

	# get values from env vars as defined by user
	export LAN_NETWORK=$(echo "${LAN_NETWORK}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ -n "${LAN_NETWORK}" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] LAN_NETWORK defined as '${LAN_NETWORK}'"
	else
		echo "$(date +'%Y-%m-%d %H:%M:%S') [ERROR] LAN_NETWORK not defined (via -e LAN_NETWORK), exiting..."
		# Sleep so it wont 'spam restart'
		sleep 10
		exit 1
	fi

	export NAME_SERVERS=$(echo "${NAME_SERVERS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ -n "${NAME_SERVERS}" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] NAME_SERVERS defined as '${NAME_SERVERS}'"
	else
		echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] NAME_SERVERS not defined (via -e NAME_SERVERS), defaulting to CloudFlare and Google name servers"
		export NAME_SERVERS="1.1.1.1,8.8.8.8,1.0.0.1,8.8.4.4"
	fi

	if [[ "${VPN_TYPE}" == "openvpn" ]]; then
		export VPN_OPTIONS=$(echo "${VPN_OPTIONS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ -n "${VPN_OPTIONS}" ]]; then
			echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] VPN_OPTIONS defined as '${VPN_OPTIONS}'"
		else
			echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] VPN_OPTIONS not defined (via -e VPN_OPTIONS)"
			export VPN_OPTIONS=""
		fi
	fi

elif [[ $VPN_ENABLED == "no" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] !!IMPORTANT!! You have set the VPN to disabled, your connection will NOT be secure!"
fi


# Split comma seperated string into list from NAME_SERVERS env variable
IFS=',' read -ra name_server_list <<< "${NAME_SERVERS}"

# Process name servers in the list
for name_server_item in "${name_server_list[@]}"; do
	# strip whitespace from start and end of lan_network_item
	name_server_item=$(echo "${name_server_item}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')

	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Adding ${name_server_item} to resolv.conf"
	echo "nameserver ${name_server_item}" >> /etc/resolv.conf
done

if [[ $VPN_ENABLED == "yes" ]]; then
	if [[ "${VPN_TYPE}" == "openvpn" ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Starting OpenVPN..."

		# Char device is only created in privileged mode; If only cap-add=NET_ADMIN is set we have to create it manually
		mkdir -p /dev/net
		if [ ! -c /dev/net/tun ]; then
			mknod /dev/net/tun c 10 200
		fi

		cd /config/openvpn
		if [[ "${VPN_OPTIONS}" != "" ]]; then
			exec openvpn --pull-filter ignore route-ipv6 --pull-filter ignore ifconfig-ipv6 "${VPN_OPTIONS}" --config "${VPN_CONFIG}" &
		else
			exec openvpn --pull-filter ignore route-ipv6 --pull-filter ignore ifconfig-ipv6 --config "${VPN_CONFIG}" &
		fi
	else
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Starting WireGuard..."
		cd /config/wireguard
		if iplink | grep $(basename "$VPN_CONFIG" .conf); then
			wg-quick down "$VPN_CONFIG" || echo "WireGuard is down already" # Run wg-quick down as an extra safeguard in case WireGuard is still up for some reason
			sleep 0.5 # Just to give WireGuard a bit to go down
		fi
		wg-quick up "$VPN_CONFIG"
	fi
	exec /bin/bash /init/iptables.sh
else
	exec /bin/bash /init/qbittorrent.sh
fi