# Custom s6-rc Extensions

The folders in this directory are examples of complete native `s6-rc` service definitions. They offer complete control compared to simply dropping a flat bash script somewhere.

If you mount custom native folders correctly, a container hook will merge them directly into the s6 supervision tree just before boot.

### `/custom-init` (Oneshot Tasks)
Components dropped here run predictably before the rest of your core stack runs. Use them to cleanly install software or set configuration parameters exactly where you need them in the dependency chain.

### `/custom-services` (Long-running Daemons)
Components dropped here will run natively supervised. If your script crashes, s6 will immediately restart it. This is highly recommended for tasks like VPN port forwarding monitors, proxies, or companion UI daemons.
