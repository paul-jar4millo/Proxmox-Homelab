#!/usr/bin/env bash
# Copy the live host and guest configuration into the repo so `git status`
# shows any drift between what runs and what is documented. Never commits:
# a human reviews and commits.
#
# Only files without secrets are exported. Passwords for notification targets
# live in /etc/pve/priv/ and are never read here; services/ (configs from
# inside the containers) is redacted by hand and not touched.
set -euo pipefail
REPO=${HOMELAB_REPO:-/root/homelab}
H=$REPO/proxmox/host

copy() { # copy SRC DEST, creating DEST's directory
    mkdir -p "$(dirname "$2")"
    cp "$1" "$2"
}

# Containers: one file per guest; drop files of destroyed guests.
mkdir -p "$REPO/proxmox/lxc"
for f in "$REPO"/proxmox/lxc/*.conf; do
    [[ -e $f ]] || continue
    [[ -e /etc/pve/lxc/$(basename "$f") ]] || git -C "$REPO" rm -q "$f" 2>/dev/null || rm -f "$f"
done
for f in /etc/pve/lxc/*.conf; do copy "$f" "$REPO/proxmox/lxc/$(basename "$f")"; done

# Host
copy /etc/network/interfaces           "$H/interfaces"
copy /etc/pve/storage.cfg              "$H/storage.cfg"
copy /etc/pve/datacenter.cfg           "$H/datacenter.cfg"
copy /etc/pve/notifications.cfg        "$H/notifications.cfg"
copy /etc/fstab                        "$H/fstab"
copy /etc/pve/firewall/cluster.fw      "$H/firewall/cluster.fw"
copy /etc/pve/nodes/"$(hostname)"/host.fw "$H/firewall/host.fw"
for f in /etc/pve/firewall/[0-9]*.fw; do [[ -e $f ]] && copy "$f" "$H/firewall/$(basename "$f")"; done
for f in /etc/cron.d/homelab-*;      do copy "$f" "$H/cron.d/$(basename "$f")"; done
copy /etc/ssh/sshd_config.d/10-homelab-hardening.conf "$H/sshd_config.d/10-homelab-hardening.conf"
copy /etc/fail2ban/jail.d/homelab.local              "$H/fail2ban/jail.d/homelab.local"
copy /etc/fail2ban/filter.d/proxmox.conf             "$H/fail2ban/filter.d/proxmox.conf"
copy /etc/systemd/journald.conf.d/10-homelab.conf    "$H/journald.conf.d/10-homelab.conf"
copy /etc/apt/apt.conf.d/52homelab-unattended        "$H/apt/52homelab-unattended"
pveversion -v > "$H/pveversion.txt"

git -C "$REPO" status --short
