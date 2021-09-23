#!/usr/bin/with-contenv bash
# shellcheck shell=bash

if [[ ${INSTALL_PYTHON3,,} == "yes" ]]; then
	if [ ! -e /usr/bin/python3 ]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Python3 not yet installed, installing..."
		apk add --no-cache python3
	else
		echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] Python3 is already installed, nothing to do."
	fi
fi