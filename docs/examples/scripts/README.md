# Custom script examples

## fw-custom-app
Shows how to let a custom application through the firewall. Mount this as a script in `/custom-cont-init.d/`.

## install-run-custom-app
Shows how to install software during initialization. This approach spawns the application in the background directly from the init script, meaning it won't be automatically restarted if it fails. Mount this to `/custom-cont-init.d/`.

*For long-running managed background daemons, consider mapping native s6-rc component bundles to `/custom-services/` instead. Check the `../s6-rc/` examples directory.*
