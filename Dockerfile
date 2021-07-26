FROM alpine:3.14

RUN \
    apk update; \

    # Install build dependencies
    apk add --no-cache --virtual .build-deps autoconf automake build-base cmake curl git libtool linux-headers perl pkgconf python3 python3-dev re2c tar \
    icu-dev libexecinfo-dev openssl-dev qt5-qtbase-dev qt5-qttools-dev zlib-dev qt5-qtsvg-dev ninja boost-dev; \

    # Compile and install Libtorrent
    git clone --shallow-submodules --recurse-submodules https://github.com/arvidn/libtorrent.git ~/libtorrent && cd ~/libtorrent; \
    git checkout "$(git tag -l --sort=-v:refname "v2*" | head -n 1)"; \
    cmake -Wno-dev -G Ninja -B build \
        -D CMAKE_BUILD_TYPE="Release" \
        -D CMAKE_CXX_STANDARD=17 \
        -D CMAKE_INSTALL_LIBDIR="lib" \
        -D CMAKE_INSTALL_PREFIX="/usr/local"; \
    cmake --build build; \
    cmake --install build; \

    # Compile and install qBittorrent
    git clone --shallow-submodules --recurse-submodules https://github.com/qbittorrent/qBittorrent.git ~/qbittorrent && cd ~/qbittorrent; \
    git checkout "$(git tag -l --sort=-v:refname | head -n 1)"; \
    cmake -Wno-dev -G Ninja -B build \
        -D CMAKE_BUILD_TYPE="release" \
        -D CMAKE_CXX_STANDARD=17 \
        -D CMAKE_CXX_STANDARD_LIBRARIES="/usr/lib/libexecinfo.so" \
        -D CMAKE_INSTALL_PREFIX="/usr/local" \
        -D GUI=OFF; \
    cmake --build build; \
    cmake --install build; \

    # Clean up
    apk del --no-cache --purge .build-deps; \
    rm -rf ~/qbittorrent* ~/libtorrent*; \
    rm -rf \
    /tmp/* \
    /var/tmp; \

    # Install tools needed at runtime
    apk add --no-cache \
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

    # Create directories
    mkdir -p /downloads /config/qBittorrent /etc/openvpn /etc/qbittorrent

VOLUME /config /downloads

COPY openvpn/ /etc/openvpn/
COPY qbittorrent/ /etc/qbittorrent/

# Make scripts executable
RUN chmod +x /etc/qbittorrent/*.sh /etc/openvpn/*.sh

# qBittorrent ports
EXPOSE 8080
EXPOSE 8999
EXPOSE 8999/udp

CMD ["/bin/bash", "/etc/openvpn/start.sh"]