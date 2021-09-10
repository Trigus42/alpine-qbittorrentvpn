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
* BitTorrent port 8999 exposed by default

## Software
* Base: alpine
* [qBittorrent](https://github.com/qbittorrent/qBittorrent) compiled from source
* [libtorrent](https://github.com/arvidn/libtorrent) compiled from source
* WireGuard / OpenVPN

## Run container
&NewLine;
### Build it yourself
&NewLine;
```sh
$ git clone https://github.com/Trigus42/alpine-qbittorrentvpn.git
$ cd qbittorrentvpn
$ docker build -t qbittorrentvpn .
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

### From the Docker registry
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

### Run in unprivileged mode
(Omit the `--privileged` flag - mainly for security)

&NewLine;
#### Wireguard:
&NewLine;
```sh
-e "UNPRIVILEGED=yes" \
--cap-add=NET_ADMIN \
--cap-add=SYS_MODULE \
--sysctl net.ipv4.conf.all.src_valid_mark=1 \
```

#### OpenVPN:
&NewLine;
```sh
--cap-add=NET_ADMIN \
```

## Docker Tags

#### **Current**

| Tag | Description |
|----------|----------|
| `trigus42/qbittorrentvpn` | The latest image with the then latest version of qBittorrent |
| `trigus42/qbittorrentvpn:YYYYMMDD` | Image build on YYYYMMDD with the then latest version of qBittorrent |
| `trigus42/qbittorrentvpn:qbtx.x.x` | Image with version x.x.x of qBittorrent |
| `trigus42/qbittorrentvpn:qbtx.x.x-YYYYMMDD` | Image build on YYYYMMDD with version x.x.x of qBittorrent |
| `trigus42/qbittorrentvpn:testing` | Unstable, untested image (not recommended) |

#### **Old**

| Tag | Description |
|----------|----------|
| `trigus42/qbittorrentvpn:alpine-YYYYMMDD` | Same as `trigus42/qbittorrentvpn:YYYYMMDD` |

## Variables, Volumes, and Ports
### Environment Variables
| Variable | Required | Function | Example | Default |
|----------|----------|----------|----------|----------|
|`VPN_ENABLED`| Yes | Enable VPN (yes/no)?|`VPN_ENABLED=yes`|`yes`|
|`VPN_TYPE`| Yes | WireGuard or OpenVPN (wireguard/openvpn)?|`VPN_TYPE=openvpn`|`wireguard`|
|`UNPRIVILEGED`| No | Allows container to run in unprivileged mode when wireguard is used |`UNPRIVILEGED=yes`|`no`|
|`VPN_USERNAME`| No | If username and password provided, configures ovpn file automatically |`VPN_USERNAME=ad8f64c02a2de`||
|`VPN_PASSWORD`| No | If username and password provided, configures ovpn file automatically |`VPN_PASSWORD=ac98df79ed7fb`||
|`LAN_NETWORK`| No | Comma delimited local Network's with CIDR notation |`LAN_NETWORK=192.168.0.0/24,10.10.0.0/24`||
|`SET_FWMARK`| No | Make web interface reachable for devices in networks not specified in `LAN_NETWORK` |`yes`|`no`|
|`ENABLE_SSL`| No | Let the container handle SSL (yes/no) |`ENABLE_SSL=yes`|`no`|
|`NAME_SERVERS`| No | Comma delimited name servers |`NAME_SERVERS=1.1.1.1,1.0.0.1`|`1.1.1.1,1.0.0.1`|
|`PUID`| No | UID applied to /config files and /downloads |`PUID=99`|`99`|
|`PGID`| No | GID applied to /config files and /downloads  |`PGID=100`|`100`|
|`UMASK`| No | |`UMASK=002`|`002`|
|`HEALTH_CHECK_HOST`| No | This is the host or IP that the healthcheck script will use to check an active connection |`HEALTH_CHECK_HOST=one.one.one.one`|`one.one.one.one`|
|`HEALTH_CHECK_INTERVAL`| No | This is the time in seconds that the container waits to see if the internet connection still works (check if VPN died) |`HEALTH_CHECK_INTERVAL=300`|`300`|
|`HEALTH_CHECK_SILENT`| No | Set to `1` to supress the 'Network is up' message. Defaults to `1` if unset |`HEALTH_CHECK_SILENT=1`|`1`|
|`INSTALL_PYTHON3`| No | Set this to `yes` to let the container install Python3 |`INSTALL_PYTHON3=yes`|`no`|
|`ADDITIONAL_PORTS`| No | Adding a comma delimited list of ports will allow these ports via the iptables script |`ADDITIONAL_PORTS=1234,8112`||
|`DEBUG`| No | Print information useful for debugging in log |`yes`|`no`|

### Volumes
| Volume | Required | Function | Example |
|----------|----------|----------|----------|
| `config` | Yes | qBittorrent, WireGuard and OpenVPN config files | `/your/config/path/:/config`|
| `downloads` | No | Default downloads path for saving downloads | `/your/downloads/path/:/downloads`|

### Ports
| Port | Proto | Required | Function | Example |
|----------|----------|----------|----------|----------|
| `8080` | TCP | Yes | qBittorrent WebUI | `8080:8080`|

## Access the WebUI
Access https://IPADDRESS:PORT from a browser on the same network. (for example: https://192.168.0.90:8080)

### Default Credentials

| Credential | Default Value |
|----------|----------|
|`username`| `admin` |
|`password`| `adminadmin` |

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

## Issues
If you are having issues with this container please submit an issue on GitHub.  
Please provide logs, Docker version and other information that can simplify reproducing the issue.  
If possible, always use the most up to date version of Docker, you operating system, kernel and the container itself. Support is always a best-effort basis.

## Credits:
This image is based on [DyonR/docker-qbittorrentvpn](https://github.com/DyonR/docker-qbittorrentvpn) which in turn is based off on [MarkusMcNugen/docker-qBittorrentvpn](https://github.com/MarkusMcNugen/docker-qBittorrentvpn) and [binhex/arch-qbittorrentvpn](https://github.com/binhex/arch-qbittorrentvpn).
