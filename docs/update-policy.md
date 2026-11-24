# Update policy

Why guests fell behind, the rules that keep them current, and what enforces
each rule.

## What happened (2026-11-23 audit)

- **CT 113 was still on Debian 12 (bookworm)** while the host and every other
  Debian guest were on 13 (trixie). `apt dist-upgrade` never changes the
  release, so the weekly updater kept it patched but never moved it forward,
  and nothing reported the difference. Bookworm left regular security support
  in June 2026 and is now on LTS.
- **CT 205 had 60 pending packages.** It had been created from the template
  the same day, after the weekly run. New guests started out of date and
  stayed that way until the next Saturday.
- **Failures were silent.** `update-lxcs.sh` skipped a guest whose pre-update
  backup failed, logged it to a file and exited 0. Nobody reads that file.
  Stopped containers were never updated or reported.

## Rules

| # | Rule | Enforced by |
|---|---|---|
| 1 | Every guest runs the **current release**: Debian = the host's release, Ubuntu = current LTS | Audit at the end of `update-lxcs.sh` mails a warning for any guest on another release |
| 2 | Packages are updated **weekly** (Saturday), after a local backup | `update-lxcs.sh` via `/etc/cron.d/homelab-update-lxcs` |
| 3 | Any failure or skipped guest **reaches a human** the same day | `lib/common.sh` → mail → Proxmox notifications → Gmail |
| 4 | A **new guest is fully updated before it goes into service** | Provisioning checklist below |
| 5 | A **major release upgrade happens within 3 months** of a new Debian stable or Ubuntu LTS, once the release has a point release (x.1) | Release warning from rule 1 repeats weekly until it is done |
| 6 | Stopped guests are either started for updates or destroyed. **No guest stays stopped for more than 2 weeks.** | Audit warns weekly about every stopped guest |
| 7 | The host gets security fixes **daily** and everything else **weekly**; reboots are manual and announced | `unattended-upgrades` (Debian-Security only) + `update-host.sh` |
| 8 | The repo matches the host | `update-host.sh` runs `export-config.sh` and warns about uncommitted drift |

## Provisioning checklist (new container)

1. Download the newest template first: `pveam update && pveam available --section system`.
2. Create with the naming scheme (`net-*` 1xx, `app-*` 2xx, `ops-*` 3xx),
   unprivileged, static IP, `nameserver 192.168.1.3` (AdGuard).
3. Before installing anything: `apt-get update && apt-get full-upgrade -y`.
4. Run `scripts/export-config.sh`, commit the new `proxmox/lxc/<id>.conf` and
   add the guest to the README.
5. The next `backup-offsite.sh` picks it up automatically. Check the next
   weekly report lists it.

## Major release upgrade procedure (e.g. CT 113 bookworm → trixie)

1. Read the service's own notes. Nginx Proxy Manager depends on the Node.js
   version from its installer, so check that it supports the target release.
2. `vzdump 113 --storage local --mode stop` (the rollback point).
3. Inside the guest: `apt full-upgrade`, then switch `bookworm` → `trixie` in
   `/etc/apt/sources.list*`, then `apt update && apt full-upgrade`, then reboot.
4. Verify the service, then run `update-lxcs.sh 113` and confirm the audit no
   longer warns.
5. Rollback if needed: `pct restore 113 <dump> --force 1`.

## Pending from the audit

- [ ] CT 113 `net-nginx-proxy-manager`: bookworm → trixie (procedure above).
      The weekly audit warns about it until it is done.
