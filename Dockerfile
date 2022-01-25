FROM alpine:3.14

# You can find the available package versions at https://pkgs.alpinelinux.org/packages?name=qbittorrent-nox
ARG QBITTORRENT_VERSION="4.3.8-r0"
# You can find the available release tags at https://github.com/just-containers/s6-overlay/releases
ARG S6_OVERLAY_VERSION="v2.2.0.3"

# Exit if one of the cont-init.d scripts fails
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

RUN \
    # Install tools
    apk add --no-cache \
        bash \
        wget \
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
        libexecinfo \
        tzdata; \
    # Install qbittorrent-nox
    apk add --no-cache \
        -X http://dl-cdn.alpinelinux.org/alpine/edge/main \
        -X http://dl-cdn.alpinelinux.org/alpine/edge/community \
        -X http://dl-cdn.alpinelinux.org/alpine/edge/testing \
        qbittorrent-nox=${QBITTORRENT_VERSION}; \
    exit 0

# Install s6-overlay
COPY ./build/s6-overlay-arch /tmp/s6-overlay-arch
RUN \
    wget https://github.com/just-containers/s6-overlay/releases/download/${S6_OVERLAY_VERSION}/s6-overlay-$(/tmp/s6-overlay-arch).tar.gz -O /tmp/s6_overlay.tar.gz; \
    tar xzf /tmp/s6_overlay.tar.gz -C /; \
    rm -r /tmp/*

COPY rootfs /

VOLUME /config /downloads
EXPOSE 8080

CMD ["/init"]