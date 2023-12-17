# qBittorrentVPN
[![Codacy Badge](https://api.codacy.com/project/badge/Grade/d10a568dc319461b844c49d8535150a3)](https://app.codacy.com/gh/Trigus42/alpine-qbittorrentvpn?utm_source=github.com&utm_medium=referral&utm_content=Trigus42/alpine-qbittorrentvpn&utm_campaign=Badge_Grade_Settings)
[![Docker Pulls](https://badgen.net/docker/pulls/trigus42/qbittorrentvpn)](https://hub.docker.com/r/trigus42/qbittorrentvpn)
[![Docker Image Size (tag)](https://badgen.net/docker/size/trigus42/qbittorrentvpn/latest)](https://hub.docker.com/r/trigus42/qbittorrentvpn)

Docker container which runs the latest qBittorrent-nox client while connecting to WireGuard or OpenVPN with netfilter killswitch to prevent IP leakage when the tunnel goes down.

## Features

* Build for **amd64**, **arm64**, **armv8** and **armv7**
* Selectively enable or disable WireGuard or OpenVPN support
* IP tables killswitch to prevent IP leaking when VPN connection fails
* Configurable UID and GID for config files and /downloads for qBittorrent
* ...

## Software
* [alpine](https://hub.docker.com/_/alpine) (base image)
* [qBittorrent](https://github.com/qbittorrent/qBittorrent)
* [WireGuard](https://www.wireguard.com/) / [OpenVPN](https://github.com/OpenVPN/openvpn)
* ...

# Run container:

Create a docker compose file or modify one of the [example compose files](examples/compose) to your needs. Then start the container by running:

```sh
docker compose up -d
```

## CLI

&NewLine;
```sh
$ docker run --privileged -d \
             -v /your/config/path/:/config \
             -v /your/downloads/path/:/downloads \
             -e "VPN_TYPE=wireguard" \
             -p 8080:8080 \
             --restart unless-stopped \
             trigus42/qbittorrentvpn
```

## Unprivileged mode
(Omit the `--privileged` flag - mainly for security)

&NewLine;
#### Wireguard:
&NewLine;
```sh
--cap-add=NET_ADMIN \
--sysctl net.ipv4.conf.all.src_valid_mark=1 \
```

#### OpenVPN:
&NewLine;
```sh
--cap-add=NET_ADMIN \
```

&NewLine;

## Image Tags

| Tag | Description |
|----------|----------|
| `trigus42/qbittorrentvpn:latest` | The latest image with the most recent version of qBittorrent |
| `trigus42/qbittorrentvpn:qbtx.x.x` | Image with qBittorrent version x.x.x |
| `trigus42/qbittorrentvpn:qbtx.x.x-YYYYMMDD` | Image built on YYYYMMDD with qBittorrent version x.x.x |
| `trigus42/qbittorrentvpn:COMMIT-HASH` | Image built from the commit with corresponding SHA hash |
| `trigus42/qbittorrentvpn:COMMIT-HASH-qbtx.x.x` | Image built from the commit with corresponding SHA hash and qBittorrent version x.x.x |
| `trigus42/qbittorrentvpn:BRANCH` | Image build from the corresponding branch |

## Environment Variables
| Variable | Function | Example | Default |
|----------|----------|----------|----------|
|`ADDITIONAL_PORTS`| Comma delimited list of ports which will be whitelisted in the firewall |`ADDITIONAL_PORTS=1234,8112`||
|`DEBUG`| Print information useful for debugging in log |`yes`|`no`|
|`DOWNLOAD_DIR_CHOWN`| Whether or not to chown files in the `/downloads` directory to PUID and PGID |`no`|`yes`|
|`ENABLE_SSL`| Let the container handle SSL (yes/no) |`ENABLE_SSL=yes`|`no`|
|`HEALTH_CHECK_HOST`| This is the host or IP that the healthcheck script will use to check an active connection |`HEALTH_CHECK_HOST=8.8.8.8`|`1.1.1.1`|
|`HEALTH_CHECK_INTERVAL`| Time in seconds that the container waits to see if the VPN and internet connection still work |`HEALTH_CHECK_INTERVAL=5`|`5`|
|`HEALTH_CHECK_TIMEOUT`| How long to wait for the internet connection to restore before restarting |`HEALTH_CHECK_INTERVAL=5`|`5`|
|`LAN_NETWORK`| Comma delimited local networks with CIDR notation |`LAN_NETWORK=192.168.0.0/16,192.168.178.0/24`||
|`NAME_SERVERS`| Comma delimited name servers |`NAME_SERVERS=1.1.1.1,1.0.0.1`|`1.1.1.1,1.0.0.1`|
|`PGID`| GID to be applied to /config files and /downloads  |`PGID=100`|`1000`|
|`PUID`| UID that qBt will be run as and to be applied to /config files and /downloads |`PUID=99`|`1000`|
|`TZ`| Specify a timezone to use |`TZ=Europe/London`|`UTC`|
|`UMASK`| Set file mode creation mask |`UMASK=002`|`002`|
|`VPN_ENABLED`| Enable VPN (yes/no)?|`VPN_ENABLED=yes`|`yes`|
|`VPN_PASSWORD`| If username and password provided, configures all ovpn files automatically |`VPN_PASSWORD=ac98df79ed7fb`||
|`VPN_TYPE`| WireGuard or OpenVPN (wireguard/openvpn)?|`VPN_TYPE=openvpn`|`wireguard`|
|`VPN_USERNAME`| If username and password provided, configures all ovpn files automatically |`VPN_USERNAME=ad8f64c02a2de`||

## Volumes
| Volume | Required | Function | Example |
|----------|----------|----------|----------|
| `config` | Yes | qBittorrent, WireGuard and OpenVPN config files | `/your/config/path/:/config`|
| `downloads` | No | Default downloads path for saving downloads | `/your/downloads/path/:/downloads`|

## Ports
| Port | Proto | Required | Function | Example |
|----------|----------|----------|----------|----------|
| `8080` | TCP | Yes | qBittorrent WebUI | `8080:8080`|


## Default Credentials

| Credential | Default Value |
|----------|----------|
|`username`| `admin` |
|`password`| `adminadmin` |

## VPN Configuration
If there are multiple config files present, one will be choosen randomly.

## WireGuard 
The container will fail to boot if `VPN_ENABLED` is set and there is no valid `INTERFACE.conf` file present in the `/config/wireguard` directory. Drop a `.conf` file from your VPN provider into `/config/wireguard` and start the container again.

> Recommended INTERFACE names include `wg0` or `wgvpn0` or even `wgmgmtlan0`. However, the number at the end is in fact optional, and really any free-form string `[a-zA-Z0-9_=+.-]{1,15}` will work. So even interface names corresponding to geographic locations would suffice, such as `cincinnati`, `nyc`, or `paris`, if that's somehow desirable. 
[[source]](https://www.man7.org/linux/man-pages/man8/wg-quick.8.html)

## OpenVPN
The container will fail to boot if `VPN_ENABLED` is set and there is no valid `FILENAME.ovpn` file present in the `/config/openvpn` directory. Drop a `.ovpn` file from your VPN provider into `/config/openvpn` (if necessary with additional files like certificates) and start the container again.  
You can either use the environment variables `VPN_USERNAME` and `VPN_PASSWORD` or store your credentials in `openvpn/credentials.conf`. Those credentials will be used to create credential files for all VPN configs initially. 
If you manually store your VPN credentials in `openvpn/FILENAME_credentials.conf`, those will be used for the particular VPN config.

#### Example credentials file
```
YOURUSERNAME
YOURPASSWORD
```

## PUID/PGID
User ID (PUID) and Group ID (PGID) can be found by issuing the following command for the user you want to run the container as:

```sh
id <username>
```

# Customization
Just mount your script to /etc/cont-init.d/ in the container. The execution order is determined by the number prefix. See [examples/scripts](examples/scripts) for examples.

## Firewall
To add custom firewall rules, you can use iptables or nftables. 

# Build it yourself
&NewLine;
You can use the `Dockerfile` with all architectures and versions of qBT that are listed [here](https://github.com/userdocs/qbittorrent-nox-static/releases).
`Dockerfile.compile` should work for all architectures. Release tags can be found [here](https://github.com/qbittorrent/qBittorrent/tags).

If you don't specify any tags, the latest release version will be used.

&NewLine;
```sh
$ git clone https://github.com/Trigus42/alpine-qbittorrentvpn.git
$ cd alpine-qbittorrentvpn

$ QBITTORRENT_TAG={TAG} docker build -f Dockerfile -t qbittorrentvpn .
-- OR --
$ QBITTORRENT_TAG={TAG} docker build -f Dockerfile.compile -t qbittorrentvpn .
```

Build for all supported architectures:
```
$ QBITTORRENT_TAG={TAG} docker buildx bake -f bake.yml
```

If you want to use this command to push the images to a registry (append `--push` to the above command), you have to modify the `image` setting in `bake.yml`.

Compiling for many architectures simultaneously can be very demanding. You can create and use a builder instance with no concurrency using these commands: 
```sh
$ docker buildx create --config buildkitd.toml --name no_concurrency
$ QBITTORRENT_TAG={TAG} docker buildx bake -f bake.yml --builder no_concurrency
```

# Reporting Issues

When encountering an issue, please first attempt to reproduce it using the most up-to-date stable versions of Docker, your operating system, kernel, and the container itself.

Upon opening an issue, kindly provide the following details:

- Full logs from container boot to exit, preferably with the `DEBUG=true` environment variable set.
- Your Docker compose file or Docker run command.
- Depending on your situation, other relevant information such as:
  - The image where the issue first arose. Including tag information such as date and commit hash can be immensely useful, especially if you suspect that a recent change may have introduced the problem.
  - Your VPN config file, with any keys and other sensitive information removed.
  - Any additional details that may be relevant to your specific situation.

While logs should not display passwords and keys, it is highly recommended to review them for any sensitive information. Depending on your particular case, you might also want to redact IP addresses and domain names.

Before opening a new issue, please refer to previously reported issues as well as the [Known Issues](https://github.com/Trigus42/alpine-qbittorrentvpn/wiki/Known-Issues) page in the wiki. Your issue might have already been addressed, or there may be ongoing discussions that you can join.

# Credits:
This image is based on [DyonR/docker-qbittorrentvpn](https://github.com/DyonR/docker-qbittorrentvpn) which in turn is based off on [MarkusMcNugen/docker-qBittorrentvpn](https://github.com/MarkusMcNugen/docker-qBittorrentvpn) and [binhex/arch-qbittorrentvpn](https://github.com/binhex/arch-qbittorrentvpn).
