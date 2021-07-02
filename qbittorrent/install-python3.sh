#!/bin/bash
if [ ! -e /usr/bin/python3 ]; then
	echo "[INFO] Python3 not yet installed, installing..." | date +'%Y-%m-%d %H:%M:%S'
	apk add --no-cache python3
else
	echo "[INFO] Python3 is already installed, nothing to do." | date +'%Y-%m-%d %H:%M:%S'
fi