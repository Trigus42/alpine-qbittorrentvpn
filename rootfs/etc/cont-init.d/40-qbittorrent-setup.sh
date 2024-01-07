#!/usr/bin/with-contenv bash
# shellcheck shell=bash

# Create /config/qBittorrent (if it doesn't exist)
mkdir -p /config/qBittorrent/config

# Set the rights on the /config/qBittorrent
chown -R "${PUID}":"${PGID}" /config/qBittorrent

# Set the rights on the /downloads folder
if [[ $DOWNLOAD_DIR_CHOWN != "no" ]]; then
	chown -R "${PUID}":"${PGID}" /downloads
fi

qbt_config_path="/config/qBittorrent/config/qBittorrent.conf"

# Check if qBittorrent.conf exists, if not, copy the template over
if [ ! -e $qbt_config_path ]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] qBittorrent.conf is missing, this is normal for the first launch! Copying template."
	cp /defaults/qBittorrent.conf $qbt_config_path
	chmod 755 $qbt_config_path
	chown "${PUID}":"${PGID}" $qbt_config_path
fi

# The mess down here checks if SSL is enabled.
if [[ ${ENABLE_SSL,,} == 'yes' ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] ENABLE_SSL is set to ${ENABLE_SSL}"
	if [[ ${HOST_OS,,} == 'unraid' ]]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [SYSTEM] If you use Unraid, and get something like a 'ERR_EMPTY_RESPONSE' in your browser, add https:// to the front of the IP, and/or do this:"
		echo "$(date +'%Y-%m-%d %H:%M:%S') [SYSTEM] Edit this Docker, change the slider in the top right to 'advanced view' and change http to https at the WebUI setting."
	fi
	if [ ! -e /config/qBittorrent/config/WebUICertificate.crt ]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] WebUI Certificate is missing, generating a new Certificate and Key"
		openssl req -new -x509 -nodes -out /config/qBittorrent/config/WebUICertificate.crt -keyout /config/qBittorrent/config/WebUIKey.key -subj "/C=NL/ST=localhost/L=localhost/O=/OU=/CN="
		chown -R "${PUID}":"${PGID}" /config/qBittorrent/config
	elif [ ! -e /config/qBittorrent/config/WebUIKey.key ]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] WebUI Key is missing, generating a new Certificate and Key"
		openssl req -new -x509 -nodes -out /config/qBittorrent/config/WebUICertificate.crt -keyout /config/qBittorrent/config/WebUIKey.key -subj "/C=NL/ST=localhost/L=localhost/O=/OU=/CN="
		chown -R "${PUID}":"${PGID}" /config/qBittorrent/config
	fi
	if grep -Fxq 'WebUI\HTTPS\CertificatePath=/config/qBittorrent/config/WebUICertificate.crt' "$qbt_config_path"; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] $qbt_config_path already has the line WebUICertificate.crt loaded, nothing to do."
	else
		echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] $qbt_config_path doesn't have the WebUICertificate.crt loaded. Added it to the config."
		echo 'WebUI\HTTPS\CertificatePath=/config/qBittorrent/config/WebUICertificate.crt' >> "$qbt_config_path"
	fi
	if grep -Fxq 'WebUI\HTTPS\KeyPath=/config/qBittorrent/config/WebUIKey.key' "$qbt_config_path"; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] $qbt_config_path already has the line WebUIKey.key loaded, nothing to do."
	else
		echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] $qbt_config_path doesn't have the WebUIKey.key loaded. Added it to the config."
		echo 'WebUI\HTTPS\KeyPath=/config/qBittorrent/config/WebUIKey.key' >> "$qbt_config_path"
	fi
	if grep -xq 'WebUI\\HTTPS\\Enabled=true\|WebUI\\HTTPS\\Enabled=false' "$qbt_config_path"; then
		if grep -xq 'WebUI\\HTTPS\\Enabled=false' "$qbt_config_path"; then
			echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] $qbt_config_path does have the WebUI\HTTPS\Enabled set to false, changing it to true."
			sed -i 's/WebUI\\HTTPS\\Enabled=false/WebUI\\HTTPS\\Enabled=true/g' "$qbt_config_path"
		else
			echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] $qbt_config_path does have the WebUI\HTTPS\Enabled already set to true."
		fi
	else
		echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] $qbt_config_path doesn't have the WebUI\HTTPS\Enabled loaded. Added it to the config."
		echo 'WebUI\HTTPS\Enabled=true' >> "$qbt_config_path"
	fi
else
	echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] ENABLE_SSL is set to ${ENABLE_SSL}, SSL is not enabled. This could cause issues with logging if other apps use the same Cookie name (SID)."
	echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] If you manage the SSL config yourself, you can ignore this."
fi

# Set the umask
if [[ -n "${UMASK}" ]]; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] UMASK defined as '${UMASK}'"
	UMASK=$(echo "${UMASK}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	export UMASK
else
	echo "$(date +'%Y-%m-%d %H:%M:%S') [WARNING] UMASK not defined (via -e UMASK), defaulting to '002'"
	export UMASK="002"
fi

# Set WebUI password
if [[ -n "${WEBUI_PASSWORD}" ]] && ! grep -Exq 'WebUI\\Password_PBKDF2=.+' "$qbt_config_path"; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Setting WebUI password to WEBUI_PASSWORD"
	salt="$(dd if=/dev/urandom bs=16 count=1 status=none | base64)"
	key="$(/helper/dwk "$WEBUI_PASSWORD" "$salt" | head -2 | tail -1)"
	sed -i "/\[Preferences\]/a WebUI\\\Password_PBKDF2=\"@ByteArray($salt:$key)\"" "$qbt_config_path"
elif ! grep -Exq 'WebUI\\Password_PBKDF2=.+' "$qbt_config_path"; then
	echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] WebUI password not set. To access the WebUI set a password or get a temporary password from the qBittorrent logs."
fi

##########
# Save envirnonment variables

CONT_INIT_ENV="/var/run/s6/container_environment"
mkdir -p $CONT_INIT_ENV
export_vars=("UMASK")

for name in "${export_vars[@]}"; do
	echo -n "${!name}" > "$CONT_INIT_ENV/$name"
done
