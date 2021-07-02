#!/bin/bash
nice docker buildx build --push --platform linux/arm/v7,linux/amd64 -t trigus42/qbittorrentvpn -t trigus42/qbittorrentvpn:alpine-$(date +'%Y%m%d') .