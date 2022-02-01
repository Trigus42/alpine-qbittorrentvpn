FROM alpine:3.14

# You can find the available package versions at https://pkgs.alpinelinux.org/packages?name=qbittorrent-nox
ARG QBITTORRENT_VERSION="4.4.0-r0"
# You can find the available release tags at https://github.com/just-containers/s6-overlay/releases
ARG S6_OVERLAY_VERSION="v2.2.0.3"

# Exit if one of the cont-init.d scripts fails
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

COPY ./build/s6-overlay-arch /tmp/s6-overlay-arch
COPY rootfs /

RUN \
    # Install tools
    apk add --no-cache \
        bash \
        dos2unix \
        grep \
        ipcalc \
        iptables \
        iputils \
        libexecinfo \
        net-tools \
        openresolv \
        openssl \
        openvpn \
        qt5-qtbase \
        tzdata \
        wget \
        wireguard-tools; \
    # Install qbittorrent-nox
    apk add --no-cache \
        -X http://dl-cdn.alpinelinux.org/alpine/edge/main \
        -X http://dl-cdn.alpinelinux.org/alpine/edge/community \
        -X http://dl-cdn.alpinelinux.org/alpine/edge/testing \
        qbittorrent-nox=${QBITTORRENT_VERSION}; \
    # Install s6-overlay
    chmod +x /tmp/s6-overlay-arch; \
    wget https://github.com/just-containers/s6-overlay/releases/download/${S6_OVERLAY_VERSION}/s6-overlay-$(/tmp/s6-overlay-arch).tar.gz -O /tmp/s6_overlay.tar.gz; \
    tar -xf /tmp/s6_overlay.tar.gz -C /; \
    rm -r /tmp/*; \
    # Set exec permissions
    chmod +x -R /helper/ /etc/cont-init.d/ /etc/services.d/

VOLUME /config /downloads
EXPOSE 8080

CMD ["/init"]