#!/usr/bin/env bash
# Weekly full upgrade of the Proxmox host itself (Saturday, after the
# containers). Security fixes already arrive daily via unattended-upgrades;
# this picks up everything else, including Proxmox and kernel packages.
#
# The host is never rebooted automatically: a reboot takes DNS, cameras and
# VPN down, so it is announced by mail and done by hand.
#
# Also exports the live configuration into the repo and warns when the repo
# no longer matches the host (scripts/export-config.sh).
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"

log_to "$HOMELAB_LOG_DIR/update-host.log"
trap finish EXIT
acquire_lock

export DEBIAN_FRONTEND=noninteractive
apt_opts=(-q -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

log "-- apt update"
apt-get update -q || fail "apt-get update failed"
log "-- apt full-upgrade"
apt-get full-upgrade "${apt_opts[@]}" || fail "apt-get full-upgrade failed"
apt-get autoremove --purge "${apt_opts[@]}" || warn "apt-get autoremove failed"
apt-get clean

running=$(uname -r)
newest=$(find /boot -maxdepth 1 -name 'vmlinuz-*-pve' -printf '%f\n' | sed 's/^vmlinuz-//' | sort -V | tail -1)
log "-- kernel running=$running newest=$newest"
if [[ -n $newest && $running != "$newest" ]]; then
    warn "reboot pending: kernel $newest is installed, $running is running"
fi
if [[ -f /var/run/reboot-required ]]; then
    warn "reboot pending: $(tr '\n' ' ' < /var/run/reboot-required.pkgs 2>/dev/null)"
fi
pveversion | while read -r line; do log "   $line"; done

log "-- config drift"
if ! "$HOMELAB_REPO/scripts/export-config.sh"; then
    fail "export-config.sh failed"
else
    # pveversion.txt changes on every upgrade; only real config drift warns.
    drift=$(git -C "$HOMELAB_REPO" status --short -- . ':!proxmox/host/pveversion.txt')
    [[ -z $drift ]] || warn "repo differs from the live host; review and commit:
$drift"
fi
