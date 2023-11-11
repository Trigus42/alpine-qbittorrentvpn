FROM alpine:3.18

# Exit if one of the cont-init.d scripts fails
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

COPY ./build/ /tmp/build

RUN \
    # Install tools
    apk add --no-cache \
        bash \
        bind-tools \
        dos2unix \
        grep \
        ipcalc \
        iputils \
        net-tools \
        nftables \
        openresolv \
        openssl \
        openvpn \
        procps \
        qt5-qtbase \
        sed \
        tzdata \
        wget \
        wireguard-tools

# You can find the available release tags at https://github.com/just-containers/s6-overlay/releases
ARG S6_OVERLAY_TAG="v2.2.0.3"
RUN \
    # Install s6-overlay
    wget https://github.com/just-containers/s6-overlay/releases/download/${S6_OVERLAY_TAG}/s6-overlay-$(/bin/sh /tmp/build/s6-overlay-arch).tar.gz -O /tmp/s6_overlay.tar.gz && \
    tar -xf /tmp/s6_overlay.tar.gz -C /

ARG QBITTORRENT_TAG
RUN \
    # Install qbittorrent-nox
    if [ -z $QBITTORRENT_TAG ]; then QBT_DL_PATH="latest/download/$(/bin/sh /tmp/build/qbittorrent-nox-static-arch)-qbittorrent-nox"; else QBT_DL_PATH="download/$QBITTORRENT_TAG/$(/bin/sh /tmp/build/qbittorrent-nox-static-arch)-qbittorrent-nox"; fi && \
    wget -O /bin/qbittorrent-nox "https://github.com/userdocs/qbittorrent-nox-static/releases/$QBT_DL_PATH" && \
    chmod +x /bin/qbittorrent-nox

COPY rootfs /
RUN \ 
    # Set exec permissions
    chmod +x -R /helper/ /etc/cont-init.d/ /etc/services.d/ && \
    # Remove temporary files
    rm -r /tmp/*

VOLUME /config /downloads
EXPOSE 8080

CMD ["/init"]