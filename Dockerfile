FROM alpine:3.19 as go-builder

RUN apk add --no-cache go

WORKDIR /app

COPY build/dwk/* ./
RUN \
    go mod download; \
    CGO_ENABLED=0 GOOS=linux go build -o ./dwk


FROM alpine:3.19

# Exit if one of the cont-init.d scripts fails
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2

RUN \
    # Install tools
    apk add --no-cache \
        bash \
        bind-tools \
        dos2unix \
        grep \
        ipcalc \
        ipset \
        iptables \
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
        wget; \
    apk add --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing \
        wireguard-go;

COPY ./build/build-scripts /tmp/build-scripts
# You can find the available release tags at https://github.com/just-containers/s6-overlay/releases
ARG S6_OVERLAY_TAG="v3.2.0.0"
RUN \
    # Install s6-overlay
    wget https://github.com/just-containers/s6-overlay/releases/download/${S6_OVERLAY_TAG}/s6-overlay-$(/bin/sh /tmp/build-scripts/s6-overlay-arch).tar.xz -O /tmp/s6_overlay.tar.xz && \
    wget https://github.com/just-containers/s6-overlay/releases/download/${S6_OVERLAY_TAG}/s6-overlay-noarch.tar.xz -O /tmp/s6_overlay-noarch.tar.xz && \
    tar -C / -Jxpf /tmp/s6_overlay.tar.xz && \
    tar -C / -Jxpf /tmp/s6_overlay-noarch.tar.xz 

ARG QBITTORRENT_TAG
RUN \
    # Install qbittorrent-nox
    if [ -z $QBITTORRENT_TAG ]; then QBT_DL_PATH="latest/download/$(/bin/sh /tmp/build-scripts/qbittorrent-nox-static-arch)-qbittorrent-nox"; else QBT_DL_PATH="download/$QBITTORRENT_TAG/$(/bin/sh /tmp/build/qbittorrent-nox-static-arch)-qbittorrent-nox"; fi && \
    wget -O /bin/qbittorrent-nox "https://github.com/userdocs/qbittorrent-nox-static/releases/$QBT_DL_PATH" && \
    chmod +x /bin/qbittorrent-nox

COPY rootfs /

RUN \
    # Add go binaries from go-builder stage
    --mount=type=bind,from=go-builder,src=/app/,dst=/mnt/go-builder/ \
    cp /mnt/go-builder/dwk /scripts/helper/dwk

RUN \ 
    # Set exec permissions
    chmod +x -R /scripts/ /etc/s6-overlay && \
    # Remove temporary files
    rm -r /tmp/*

ARG SOURCE_COMMIT="UNSPECIFIED"
RUN \
    echo "${SOURCE_COMMIT}" > /etc/image-source-commit; \
    echo "$(date +'%Y-%m-%d %H:%M:%S')" > /etc/image-build-date

VOLUME /config /downloads
EXPOSE 8080

CMD ["/init"]