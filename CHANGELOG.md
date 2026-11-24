# Changelog

## 2026-11-23

- **Offsite backups.** New CT 301 `ops-backup` (new `ops-*` 3xx range) runs
  `rclone serve restic` on Google Drive: TLS, basic auth, append-only,
  firewall open to the host only. `backup-offsite.sh` streams every guest
  from `vzdump --stdout` into restic daily; `backup-maintenance.sh` applies
  retention, checks integrity and freshness, mails a weekly report and runs a
  monthly restore drill. Design and runbooks in `docs/backup.md`.
- **Alerts by mail.** Proxmox notification target `gmail` (SMTP) and matcher
  `alertas-gmail` (warning, error and system mail). The builtin
  `default-matcher` is disabled. All scripts share `scripts/lib/common.sh`,
  which mails failures instead of only logging them.
- **Host updates.** Upgraded 156 packages (pve-manager 9.2.20 → 9.2.32,
  kernel 7.0.14-30). Removed kernels 6.8.12-4, 6.8.12-28 and 7.0.6-2.
  Daily security updates with `unattended-upgrades`, weekly full upgrade
  with `update-host.sh`; reboots stay manual.
- **Update policy** (`docs/update-policy.md`): `update-lxcs.sh` now audits
  every guest's OS release and pending packages and mails warnings. It
  found CT 113 on Debian 12, which now has a scheduled upgrade.
- **Disk: 87 % → 50 %.** `pct fstrim` on every guest (≈ 90 GB returned by
  sparse raw images), removed the leftovers of the 15 Nov consolidation
  (`rebuild-20261115`, `secondbrain-backup`), a stale template download,
  the old cron log and a stray initramfs temp dir. journald capped at 500 MB.
- **CT 203 `app-claude` destroyed** with its backups, as planned after the
  consolidation into 204.
- **Network:** removed unused bridges `vmbr1` and `vmbr2`. Containers
  resolve through AdGuard (192.168.1.3); AdGuard itself uses Quad9, and
  Tailscale already hands AdGuard to the tailnet. Empty `tags:` removed.
- Repo synced with the host: added CT 204, 205 and 301, removed 203, plus
  `scripts/export-config.sh`. `update-host.sh` warns weekly about
  uncommitted drift.

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
