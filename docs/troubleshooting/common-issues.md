## Kernel support

### Version

Your host should have kernel version 5.4 or higher or a kernel with the necessary backports (like RHEL 4.18).

### Modules

Your kernel needs to be compiled with the necessary modules.  
Those modules should be available:
```
Module             Used by

nft_ct             
nft_chain_nat      
nf_nat             xt_nat,nft_chain_nat,xt_MASQUERADE
nf_conntrack       nft_ct,xt_nat,xt_conntrack,xt_MASQUERADE,nf_nat
nf_defrag_ipv6     nf_conntrack
nf_defrag_ipv4     nf_conntrack
nf_tables          nft_ct,nft_chain_nat,nft_compat
nfnetlink          nft_compat,nf_tables
```

Because they depend on the others, it should be enough to check for `nft_ct` and `nft_chain_nat`.

### Typical errors:

`Error: Could not process rule: No such file or directory` [(Issue)](https://github.com/Trigus42/alpine-qbittorrentvpn/issues/66)  
`Error: Could not process rule: Invalid argument` [(Issue)](https://github.com/Trigus42/alpine-qbittorrentvpn/issues/50)  
`netlink: Error: cache initialization failed: Invalid argument` [(Issue)](https://github.com/Trigus42/alpine-qbittorrentvpn/issues/52)  

## Progress lost on restart

This is a currently ongoing [issue](https://github.com/Trigus42/alpine-qbittorrentvpn/issues/65). As a temporary solution please try:

- Setting `Save resume data interval` in the advanced WebUI settings to `1` minute.
- Increasing the `HEALTH_CHECK_TIMEOUT` environment variable to `60` seconds.

## Wrong date due to outdated seccomp
```sh
/ # date
Mon Jul 26 15:00:00 UTC 2036
```

This can lead to several commands failing. For example:
```
/ # apk update
fetch https://dl-cdn.alpinelinux.org/alpine/v3.14/main/armv7/APKINDEX.tar.gz
ERROR: https://dl-cdn.alpinelinux.org/alpine/v3.14/main: temporary error (try again later)
...
```

### Solution:  
Update the libseccomp2 package on your host machine to version 2.4 or newer. If no never version is available from your sources, try to manually download and install a newer version. If you are using a Debian based distro you can find packages [here](http://ftp.debian.org/debian/pool/main/libs/libseccomp/).

Example commands for the RPi:
```
$ wget http://ftp.debian.org/debian/pool/main/libs/libseccomp/libseccomp2_2.5.1-1_armhf.deb
$ dpkg -i libseccomp2_2.5.1-1_armhf.deb
```
