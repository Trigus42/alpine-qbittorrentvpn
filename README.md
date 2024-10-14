# qBittorrentVPN
[![Codacy Badge](https://api.codacy.com/project/badge/Grade/d10a568dc319461b844c49d8535150a3)](https://app.codacy.com/gh/Trigus42/alpine-qbittorrentvpn?utm_source=github.com&utm_medium=referral&utm_content=Trigus42/alpine-qbittorrentvpn&utm_campaign=Badge_Grade_Settings)
[![Docker Pulls](https://badgen.net/docker/pulls/trigus42/qbittorrentvpn)](https://hub.docker.com/r/trigus42/qbittorrentvpn)
[![Docker Image Size (tag)](https://badgen.net/docker/size/trigus42/qbittorrentvpn/latest)](https://hub.docker.com/r/trigus42/qbittorrentvpn)

Docker container which runs the latest qBittorrent-nox client while connecting to WireGuard or OpenVPN with netfilter killswitch to prevent IP leakage when the tunnel goes down.

## Features

* Netfilter **killswitch** to prevent IP leaking when VPN connection fails
* Selectively enable or disable **WireGuard** or **OpenVPN** support
* **IPv6** support
* Configurable **UID** and **GID** for config files and /downloads for qBittorrent
* Build for **amd64**, **arm64**, **armv8** and **armv7**
* ...

# Run container:

* Modify one of the [example compose files](docs/examples/compose) to your needs.
* [Create the necessary VPN config files](#vpn-configuration).

Then start the container by running:

```sh
docker compose up -d
```

&NewLine;

## Image Tags

| Tag | Description |
|----------|----------|
| `trigus42/qbittorrentvpn:latest` | The latest image with the most recent version of qBittorrent |
| `trigus42/qbittorrentvpn:qbtx.x.x` | Image with qBittorrent version x.x.x |
| `trigus42/qbittorrentvpn:COMMIT-HASH` | Image built from the commit with corresponding SHA hash |
| `trigus42/qbittorrentvpn:COMMIT-HASH-qbtx.x.x` | Image built from the commit with corresponding SHA hash and qBittorrent version x.x.x |

WARNING: Only with the `latest` tag will you continuously receive updates.

## Environment Variables
| Variable | Function | Example | Default |
|----------|----------|----------|----------|
|`DEBUG`| Print information useful for debugging in log |`yes`|`no`|
|`DOWNLOAD_DIR_CHOWN`| Whether or not to chown files in the `/downloads` directory to PUID and PGID |`no`|`yes`|
|`ENABLE_SSL`| Let the container handle SSL (yes/no) |`yes`|`no`| 
|`HEALTH_CHECK_HOST`| This is the host or IP that the healthcheck script will use to check an active connection |`8.8.8.8`|`1.1.1.1`|
|`HEALTH_CHECK_INTERVAL`| Time in seconds that the container waits to see if the VPN and internet connection still work |`5`|`5`|
|`HEALTH_CHECK_TIMEOUT`| How long to wait for the internet connection to restore before restarting |`30`|`15`|
|`LEGACY_IPTABLES`| Use legacy iptables instead of nftables |`yes`|`no`|
|`NAME_SERVERS`| Comma delimited name servers |`1.1.1.1,1.0.0.1`|`1.1.1.1,1.0.0.1`|
|`PGID`| GID to be applied to /config files and /downloads  |`99`|`1000`|
|`PUID`| UID that qBt will be run as and to be applied to /config files and /downloads |`99`|`1000`|
|`TZ`| Specify a timezone to use |`Europe/London`|`UTC`|
|`UMASK`| Set file mode creation mask |`002`|`002`|
|`VPN_ENABLED`| Enable VPN (yes/no)?|`yes`|`yes`|
|`VPN_PASSWORD`| If username and password provided, configures all ovpn files automatically |`ac98df79ed7fb`||
|`VPN_TYPE`| WireGuard or OpenVPN (wireguard/openvpn)?|`openvpn`|`wireguard`|
|`VPN_USERNAME`| If username and password provided, configures all ovpn files automatically |`ad8f64c02a2de`||
|`WEBUI_ALLOWED_NETWORKS`| Comma delimited networks in CIDR notation. If set, only networks in this list can access the WebUI. |`192.168.0.0/16,fd5e:d5b:760a:4796::/64`||
|`WEBUI_PASSWORD`| Set WebUI password if none is set (won't change it) |`mypassword`||

## Volumes
| Volume | Required | Function | Example |
|----------|----------|----------|----------|
| `config` | Yes | qBittorrent, WireGuard and OpenVPN config files | `/your/config/path/:/config`|
| `downloads` | No | Default downloads path for saving downloads | `/your/downloads/path/:/downloads`|

## Ports
| Port | Proto | Required | Function | Example |
|----------|----------|----------|----------|----------|
| `8080` | TCP | Yes | qBittorrent WebUI | `8080:8080`|

## VPN Configuration
If there are multiple config files present, one will be choosen randomly.

## WireGuard 
The container will fail to boot if `VPN_ENABLED` is set and there is no valid `INTERFACE.conf` file present in the `/config/wireguard` directory. Drop a `.conf` file from your VPN provider into `/config/wireguard` and start the container again.

> Recommended INTERFACE names include `wg0` or `wgvpn0` or even `wgmgmtlan0`. However, the number at the end is in fact optional, and really any free-form string `[a-zA-Z0-9_=+.-]{1,15}` will work. So even interface names corresponding to geographic locations would suffice, such as `cincinnati`, `nyc`, or `paris`, if that's somehow desirable. 
[[source]](https://www.man7.org/linux/man-pages/man8/wg-quick.8.html)

## OpenVPN
The container will fail to boot if `VPN_ENABLED` is set and there is no valid `FILENAME.ovpn` file present in the `/config/openvpn` directory. Drop a `.ovpn` file from your VPN provider into `/config/openvpn` (if necessary with additional files like certificates) and start the container.  

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
Just mount your script to `/custom-cont-init.d` in the container. Those scripts are executed before any of the default init scripts.
See [docs/examples/scripts](docs/examples/scripts) for examples.  

# Build it yourself
&NewLine;
You can use the `Dockerfile` with all architectures and versions of qBT that are listed [here](https://github.com/userdocs/qbittorrent-nox-static/releases).

If you don't specify any tags, the latest release version will be used.

&NewLine;
```sh
$ git clone https://github.com/Trigus42/alpine-qbittorrentvpn.git
$ cd alpine-qbittorrentvpn
$ QBITTORRENT_TAG={TAG} docker build -f Dockerfile -t qbittorrentvpn .
```

Build for all supported architectures:
```
$ QBITTORRENT_TAG={TAG} docker buildx bake -f bake.yml
```

If you want to use this command to push the images to a registry (append `--push` to the above command), you have to modify the `image` setting in `bake.yml`.

# Reporting Issues

When encountering an issue, please first attempt to reproduce it using the most up-to-date stable versions of Docker, your operating system, kernel, and the container itself.

Before opening a new issue, please refer to previously reported issues as well as the [common issues](docs/troubleshooting/common-issues.md). Your issue might have already been addressed, or there may be ongoing discussions that you can join.

Upon opening an issue, kindly provide the following details:

- Full logs from container boot to exit, preferably with the `DEBUG=yes` environment variable set.
- Your Docker compose file or Docker run command.
- Depending on your situation, other relevant information such as:
  - The image where the issue first arose. Including tag information such as date and commit hash can be immensely useful, especially if you suspect that a recent change may have introduced the problem.
  - Your VPN config file, with any keys and other sensitive information removed.
  - Any additional details that may be relevant to your specific situation.

While logs should not display passwords and keys, it is highly recommended to review them for any sensitive information. Depending on your particular case, you might also want to redact IP addresses and domain names.

# Credits:

## Software
* [alpine](https://hub.docker.com/_/alpine) (base image)
* [qBittorrent](https://github.com/qbittorrent/qBittorrent)
* [WireGuard](https://www.wireguard.com/) / [OpenVPN](https://github.com/OpenVPN/openvpn)
* ...

## Inspiration
This image was inspired by and is partially based on [DyonR/docker-qbittorrentvpn](https://github.com/DyonR/docker-qbittorrentvpn), [MarkusMcNugen/docker-qBittorrentvpn](https://github.com/MarkusMcNugen/docker-qBittorrentvpn) and [binhex/arch-qbittorrentvpn](https://github.com/binhex/arch-qbittorrentvpn).
