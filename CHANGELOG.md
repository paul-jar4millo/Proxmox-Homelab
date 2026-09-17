# Changelog

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
