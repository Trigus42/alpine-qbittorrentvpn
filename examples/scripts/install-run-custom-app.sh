#!/usr/bin/with-contenv bash
# shellcheck shell=bash

# Install software
apk add python3 > /dev/null

# Run
python3 /my_volume/script.py &