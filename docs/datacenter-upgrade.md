# Proxmox Datacenter Upgrade

`scripts/datacenter-upgrade.sh` is the supported updater for the three-node
`chome` Proxmox cluster. It replaces the older unattended host, LXC, and
application scripts.

The updater is read-only unless `--apply` is supplied. Every mutating phase is
gated by cluster quorum, enabled storage, failed-unit checks, free root space,
known application memory minimums, and a recent backup for every non-template
guest. Running LXCs are checked for pre-existing failed units before any update
starts.

## Full upgrade

Run the full workflow from `pve2` so `pve1`, which hosts the management VM, can
be rebooted and verified before the orchestrator reboots itself:

```bash
ssh root@pve2
datacenter-upgrade --apply --phase all --reboot-hosts --firmware
```

The workflow updates:

- Debian/Ubuntu packages in all LXCs and Linux QEMU guests
- Windows guests that have a working QEMU guest agent
- Home Assistant OS, Core, Supervisor, and installed apps when updates exist
- supported application stacks, including Omada, Nextcloud, Ollama, Frigate,
  Immich, Plex, Zigbee2MQTT, Z-Wave JS UI, and the Arr services
- Proxmox packages, one host at a time
- LVFS firmware when `--firmware` is explicitly selected

On Secure Boot Proxmox hosts, the updater installs the packaged signed shim in
the standard Debian EFI namespace expected by `fwupd`. This leaves the Proxmox
boot entry unchanged while allowing supported firmware capsules to be staged
and verified normally.

The current minimum memory gates match the supported application updaters:
Tautulli and Cleanuparr require 1 GB; qBittorrent and FlareSolverr require 2 GB;
Seerr requires 4 GB. Frigate is held at a 10 GB operational floor to leave
headroom for simultaneous embedding and model-training work.

Stopped guests are returned to their original state. A guest without a working
agent is reported for manual handling rather than silently skipped. The local
orchestrator host schedules its own reboot last. Remote host shutdown allows up
to 15 minutes for large guests to stop cleanly before the reboot is considered
failed.

## Common commands

```bash
# Read-only health, backup, and upgrade report
datacenter-upgrade

# Upgrade guest operating systems only
datacenter-upgrade --apply --phase guests

# Upgrade applications only
datacenter-upgrade --apply --phase apps

# Upgrade Proxmox packages without rebooting
datacenter-upgrade --apply --phase hosts
```

Logs and machine-readable summaries are stored in
`/var/log/chome-datacenter-upgrade/` on the node that runs the workflow.
