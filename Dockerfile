FROM alpine:3.14 as builder

WORKDIR /root/

# Install build dependencies
RUN \
    apk update; \
    apk add --no-cache --virtual .build-deps autoconf automake build-base cmake curl git libtool linux-headers perl pkgconf python3 python3-dev re2c tar \
    icu-dev libexecinfo-dev openssl-dev qt5-qtbase-dev qt5-qttools-dev zlib-dev qt5-qtsvg-dev ninja boost-dev; \
    exit 0

# Compile Libtorrent
RUN \
    git clone --shallow-submodules --recurse-submodules https://github.com/arvidn/libtorrent.git libtorrent && cd libtorrent; \
    git checkout "$(git tag -l --sort=-v:refname "v2*" | head -n 1)"; \
    cmake -Wno-dev -G Ninja -B build \
        -D CMAKE_BUILD_TYPE="Release" \
        -D CMAKE_CXX_STANDARD=17 \
        -D CMAKE_INSTALL_LIBDIR="lib" \
        -D CMAKE_INSTALL_PREFIX="/usr/local"; \
    cmake --build build; \
    cmake --install build

# Compile qBittorrent
RUN \
    git clone --shallow-submodules --recurse-submodules https://github.com/qbittorrent/qBittorrent.git qbittorrent && cd qbittorrent; \
    git checkout "$(git tag -l --sort=-v:refname | head -n 1)"; \
    cmake -Wno-dev -G Ninja -B build \
        -D CMAKE_BUILD_TYPE="release" \
        -D CMAKE_CXX_STANDARD=17 \
        -D CMAKE_CXX_STANDARD_LIBRARIES="/usr/lib/libexecinfo.so" \
        -D CMAKE_INSTALL_PREFIX="/usr/local" \
        -D GUI=OFF; \
    cmake --build build

FROM alpine:3.14
    
RUN \
    # Mount files from build stage
    --mount=type=bind,from=builder,src=/root,dst=/mnt/build/ \
    # Copy build files from ro mount
    cp -r /mnt/build/libtorrent /root/; \
    cp -r /mnt/build/qbittorrent /root/; \
    # Add cmake
    apk add --no-cache cmake; \
    # Install libtorrent
    cd /root/libtorrent; \
    cmake --install build; \
    # Install qBittorrent
    cd /root/qbittorrent; \
    cmake --install build; \
    # Remove cmake
    apk del --no-cache --purge cmake; \
    # Remove build files
    rm -r /root/libtorrent /root/qbittorrent

RUN \
    # Install tools needed at runtime
    apk add --no-cache \
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

    # Create directories
    mkdir -p /downloads /config/qBittorrent /init

VOLUME /config /downloads

# Copy scripts
COPY init/ /init

# Make scripts executable
RUN chmod +x /init/*.sh

# qBittorrent ports
EXPOSE 8080

CMD ["/bin/bash", "/init/init.sh"]