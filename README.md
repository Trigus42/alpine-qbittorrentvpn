# [qBittorrent](https://github.com/qbittorrent/qBittorrent), WireGuard and OpenVPN
[![Codacy Badge](https://api.codacy.com/project/badge/Grade/d10a568dc319461b844c49d8535150a3)](https://app.codacy.com/gh/Trigus42/alpine-qbittorrentvpn?utm_source=github.com&utm_medium=referral&utm_content=Trigus42/alpine-qbittorrentvpn&utm_campaign=Badge_Grade_Settings)
[![Docker Pulls](https://badgen.net/docker/pulls/trigus42/qbittorrentvpn)](https://hub.docker.com/r/trigus42/qbittorrentvpn)
[![Docker Image Size (tag)](https://badgen.net/docker/size/trigus42/qbittorrentvpn/latest)](https://hub.docker.com/r/trigus42/qbittorrentvpn)

Docker container which runs the latest qBittorrent-nox client while connecting to WireGuard or OpenVPN with iptables killswitch to prevent IP leakage when the tunnel goes down.

## Features

* Build for **amd64**, **arm64**, **armv8** and **armv7**
* Selectively enable or disable WireGuard or OpenVPN support
* IP tables killswitch to prevent IP leaking when VPN connection fails
* Configurable UID and GID for config files and /downloads for qBittorrent

## Software
* [alpine](https://hub.docker.com/_/alpine) (base image)
* [qBittorrent](https://github.com/qbittorrent/qBittorrent)
* [libtorrent](https://github.com/arvidn/libtorrent)
* [WireGuard](https://www.wireguard.com/) / [OpenVPN](https://github.com/OpenVPN/openvpn)

# Run container:

## From the Docker registry
&NewLine;
```sh
$ docker run --privileged -d \
             -v /your/config/path/:/config \
             -v /your/downloads/path/:/downloads \
             -e "VPN_ENABLED=yes" \
             -e "VPN_TYPE=wireguard" \
             -e "LAN_NETWORK=192.168.0.0/24" \
             -p 8080:8080 \
             --restart unless-stopped \
             trigus42/qbittorrentvpn
```

## Run in unprivileged mode
(Omit the `--privileged` flag - mainly for security)

&NewLine;
#### Wireguard:
&NewLine;
```sh
--cap-add=NET_ADMIN \
--cap-add=SYS_MODULE \
--sysctl net.ipv4.conf.all.src_valid_mark=1 \
```

#### OpenVPN:
&NewLine;
```sh
--cap-add=NET_ADMIN \
```

&NewLine;
## Build it yourself
&NewLine;
You can use the `Dockerfile` with all architectures and versions of qBT that are listed [here](https://pkgs.alpinelinux.org/package/edge/testing/x86_64/qbittorrent-nox).  
You can find more information on the `Architecture` tags [here](https://wiki.alpinelinux.org/wiki/Architecture).  

The `Dockerfile.compile` should work for all architectures.

&NewLine;
```sh
$ git clone https://github.com/Trigus42/alpine-qbittorrentvpn.git
$ cd alpine-qbittorrentvpn

$ docker build -f Dockerfile -t qbittorrentvpn .
$ docker build -f Dockerfile.compile -t qbittorrentvpn .

$ docker run --privileged -d \
             -v /your/config/path/:/config \
             -v /your/downloads/path/:/downloads \
             -e "VPN_ENABLED=yes" \
             -e "VPN_TYPE=wireguard" \
             -e "LAN_NETWORK=192.168.0.0/24" \
             -p 8080:8080 \
             --restart unless-stopped \
             qbittorrentvpn
```

# Docker Tags

| Tag | Description |
|----------|----------|
| `trigus42/qbittorrentvpn` | The latest image with the then latest version of qBittorrent |
| `trigus42/qbittorrentvpn:YYYYMMDD` | Image build on YYYYMMDD with the then latest version of qBittorrent |
| `trigus42/qbittorrentvpn:qbtx.x.x` | Image with version x.x.x of qBittorrent |
| `trigus42/qbittorrentvpn:qbtx.x.x-YYYYMMDD` | Image build on YYYYMMDD with version x.x.x of qBittorrent |
| `trigus42/qbittorrentvpn:testing` | Image used for testing (don't use)|

The images of the development branch use the same naming sceme except that `dev-` is added in front.  
For example: `trigus42/qbittorrentvpn:dev-qbtx.x.x-YYYYMMDD`  
Testing and feedback is appreciated.

# Environment Variables
| Variable | Required | Function | Example | Default |
|----------|----------|----------|----------|----------|
|`VPN_ENABLED`| Yes | Enable VPN (yes/no)?|`VPN_ENABLED=yes`|`yes`|
|`VPN_TYPE`| Yes | WireGuard or OpenVPN (wireguard/openvpn)?|`VPN_TYPE=openvpn`|`wireguard`|
|`VPN_USERNAME`| No | If username and password provided, configures ovpn file automatically |`VPN_USERNAME=ad8f64c02a2de`||
|`VPN_PASSWORD`| No | If username and password provided, configures ovpn file automatically |`VPN_PASSWORD=ac98df79ed7fb`||
|`LAN_NETWORK`| No | Comma delimited local Network's with CIDR notation |`LAN_NETWORK=192.168.0.0/24,10.10.0.0/24`||
|`SET_FWMARK`| No | Make web interface reachable for devices in networks not specified in `LAN_NETWORK` |`yes`|`no`|
|`ENABLE_SSL`| No | Let the container handle SSL (yes/no) |`ENABLE_SSL=yes`|`no`|
|`NAME_SERVERS`| No | Comma delimited name servers |`NAME_SERVERS=1.1.1.1,1.0.0.1`|`1.1.1.1,1.0.0.1`|
|`PUID`| No | UID applied to /config files and /downloads |`PUID=99`|`1000`|
|`PGID`| No | GID applied to /config files and /downloads  |`PGID=100`|`1000`|
|`UMASK`| No | |`UMASK=002`|`002`|
|`HEALTH_CHECK_HOST`| No | This is the host or IP that the healthcheck script will use to check an active connection |`HEALTH_CHECK_HOST=8.8.8.8`|`1.1.1.1`|
|`HEALTH_CHECK_INTERVAL`| No | This is the time in seconds that the container waits to see if the VPN still works |`HEALTH_CHECK_INTERVAL=5`|`5`|
|`INSTALL_PYTHON3`| No | Set this to `yes` to let the container install Python3 |`INSTALL_PYTHON3=yes`|`no`|
|`ADDITIONAL_PORTS`| No | Adding a comma delimited list of ports will allow these ports via the iptables script |`ADDITIONAL_PORTS=1234,8112`||
|`DEBUG`| No | Print information useful for debugging in log |`yes`|`no`|

# Volumes
| Volume | Required | Function | Example |
|----------|----------|----------|----------|
| `config` | Yes | qBittorrent, WireGuard and OpenVPN config files | `/your/config/path/:/config`|
| `downloads` | No | Default downloads path for saving downloads | `/your/downloads/path/:/downloads`|

# Ports
| Port | Proto | Required | Function | Example |
|----------|----------|----------|----------|----------|
| `8080` | TCP | Yes | qBittorrent WebUI | `8080:8080`|

# Default Credentials

| Credential | Default Value |
|----------|----------|
|`username`| `admin` |
|`password`| `adminadmin` |

# VPN Configuration

## How to use WireGuard 
The container will fail to boot if `VPN_ENABLED` is set and there is no valid .conf file present in the /config/wireguard directory. Drop a .conf file from your VPN provider into /config/wireguard and start the container again. The file must have the name `wg0.conf`, or it will fail to start.

## How to use OpenVPN
The container will fail to boot if `VPN_ENABLED` is set and there is no valid .ovpn file present in the /config/openvpn directory. Drop a .ovpn file from your VPN provider into /config/openvpn (if necessary with additional files like certificates) and start the container again. You can either use the environment variables `VPN_USERNAME` and `VPN_PASSWORD` or manually store your VPN credentials in `openvpn/credentials.conf`.

**Note:** The script will use the first ovpn file it finds in the /config/openvpn directory. Adding multiple ovpn files will not start multiple VPN connections.

### Example credentials.conf
```
YOURUSERNAME
YOURPASSWORD
```

## PUID/PGID
User ID (PUID) and Group ID (PGID) can be found by issuing the following command for the user you want to run the container as:

```sh
id <username>
```

# Issues
If you are having issues with this container please submit an issue on GitHub.  
Please provide logs, Docker version and other information that can simplify reproducing the issue.  
If possible, always use the most up to date version of Docker, you operating system, kernel and the container itself. Support is always a best-effort basis.

# Credits:
This image is based on [DyonR/docker-qbittorrentvpn](https://github.com/DyonR/docker-qbittorrentvpn) which in turn is based off on [MarkusMcNugen/docker-qBittorrentvpn](https://github.com/MarkusMcNugen/docker-qBittorrentvpn) and [binhex/arch-qbittorrentvpn](https://github.com/binhex/arch-qbittorrentvpn).
