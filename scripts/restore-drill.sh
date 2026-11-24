#!/usr/bin/env bash
# Restore drill: prove a backup can be restored, not just that it exists.
#
# Pulls the newest offsite snapshot of a container from Google Drive, restores
# it as a throw-away guest 9<vmid> with its network removed (no IP or MAC
# clash with the original), boots it, checks systemd comes up, then destroys
# it. Prints the measured restore time, which is the real RTO for that guest.
#
# Usage: restore-drill.sh [vmid]     (default 202)
# Called monthly by backup-maintenance.sh; safe to run by hand.
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
set -a; source /root/.config/restic/homelab.env; set +a

src=${1:-202}
drill=9$src
t0=$SECONDS

cleanup() {
    # a failed pct restore kills `restic dump` mid-stream, leaving its lock;
    # unlock removes only locks whose process is gone (or > 30 min old)
    restic unlock >/dev/null 2>&1 || true
    if pct status "$drill" >/dev/null 2>&1; then
        pct stop "$drill" >/dev/null 2>&1 || true
        pct destroy "$drill" --purge 1 >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT
cleanup   # leftovers from an interrupted drill

snap=$(restic snapshots --host "$(hostname)" --tag "ct-$src" --latest 1 --json)
id=$(jq -r '.[-1].short_id // empty' <<<"$snap")
file=$(jq -r '.[-1].paths[0] // empty' <<<"$snap")
when=$(jq -r '.[-1].time // empty' <<<"$snap")
[[ -n $id ]] || { echo "no snapshot for ct-$src"; exit 1; }
echo "drill: CT $src from snapshot $id ($when) -> CT $drill"

# Restoring from a pipe, pct cannot read the disk size from the archive, so
# --rootfs is required: use the original guest's size (in GiB).
size=$(pct config "$src" | sed -n 's/^rootfs:.*size=\([0-9]*\)G.*/\1/p')
restic dump "$id" "$file" |
    pct restore "$drill" - --rootfs "local:${size:-8}" --unique 1 >/dev/null
t_restore=$(( SECONDS - t0 ))
pct set "$drill" --delete net0 --onboot 0 --hostname "drill-$src" \
    --description "restore drill of CT $src, destroyed automatically"
pct start "$drill"

state=$(timeout 180 pct exec "$drill" -- systemctl is-system-running --wait 2>/dev/null || true)
t_boot=$(( SECONDS - t0 ))
echo "drill: restored in ${t_restore}s, booted to '$state' at ${t_boot}s"
case "$state" in
    running|degraded) echo "drill: PASS (degraded is expected: the network was removed)";;
    *) echo "drill: FAIL, systemd state '$state'"; exit 1;;
esac
