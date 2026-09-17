# Changelog

## 2026-09-17 (later)

- LXC 111 (Tailscale) root filesystem hit 100 % (apt cache + journal on a
  2 GB disk); Tailscale could no longer write `resolv.conf`. Cleaned, resized
  to 4 GB, `tailscaled` restarted.
- `scripts/update-lxcs.sh` now runs `apt-get clean` after upgrading so
  containers do not accumulate package caches.
- Revoked the unused `root@pam!terraform` API token and its `TerraformProv`
  role; will be recreated when Terraform is actually adopted.
- Nginx Proxy Manager: removed 6 proxy hosts pointing at hosts that no longer
  exist (docker, pterodactyl, node1, openwebui, ha, externo). 4 remain.

## 2026-09-17

- Removed the weekly community-scripts `curl | bash` LXC updater from root's
  crontab. Replaced by `scripts/update-lxcs.sh` (Saturday 10:00), which takes
  a vzdump backup of each container before upgrading it.
- Destroyed VM 300 (Pterodactyl / Project Zomboid), idle since July. World
  backed up first.
- Renamed LXC 113 `net-npm-interno` → `net-nginx-proxy-manager`.
- Memory: AdGuard 1 → 2 GB, Frigate 2 → 3 GB. Both were swapping.
- Frigate media mount point excluded from backups (`backup=0`).
- SSH: root login is key-only, password authentication disabled.
- Proxmox firewall enabled with a `management` IPSet (LAN + tailnet); host
  accepts only SSH, web UI, SPICE and ICMP from it.
- fail2ban for sshd and the Proxmox web UI.
- Disabled the stale `/mnt/externo` fstab entry (disk not attached).
- Removed community-scripts HTML descriptions from every container config.
- Exported redacted service configs (AdGuard, Frigate, NPM) under `services/`.
- Repo created.
