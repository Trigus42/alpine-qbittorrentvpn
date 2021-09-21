FROM alpine:3.14

ARG BUILD_DATE
# You can find the available package versions at https://pkgs.alpinelinux.org/packages?name=qbittorrent-nox
ARG QBITTORRENT_VERSION="4.3.8-r0"

LABEL build_version="qBittorrent version: ${QBITTORRENT_VERSION} - Build-date: ${BUILD_DATE}"
LABEL maintainer="trigus42"

# Exit if one of the cont-init.d scripts fails
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

RUN \
    # Install tools
    apk add --no-cache \
        s6-overlay \
        bash \
        wireguard-tools \
        dos2unix \
        openvpn \
        grep \
        net-tools \
        openresolv \
        iptables \
        ipcalc \
        iputils \
        openssl \
        qt5-qtbase \
        libexecinfo; \

    # Install qbittorrent-nox
    apk add --no-cache \
        -X http://dl-cdn.alpinelinux.org/alpine/edge/main \
        -X http://dl-cdn.alpinelinux.org/alpine/edge/community \
        -X http://dl-cdn.alpinelinux.org/alpine/edge/testing \
        qbittorrent-nox=${QBITTORRENT_VERSION}

COPY rootfs /

VOLUME /config /downloads
EXPOSE 8080

CMD ["/init"]