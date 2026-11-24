#!/usr/bin/env bash
# Daily offsite backup to the restic repository on Google Drive.
#
# Every container is streamed straight from vzdump into restic: no local
# archive is written, restic deduplicates the uncompressed tar against the
# previous days, compresses it and encrypts it before it leaves the host.
# The host talks to CT 301 (rclone serve restic --append-only, TLS), so this
# script can add snapshots but cannot delete or rewrite existing data.
#
# Design and restore procedures: docs/backup.md
#
# Usage: backup-offsite.sh [vmid ...]   (no args = every container + host config)
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"

ENV_FILE=/root/.config/restic/homelab.env
EXCLUDES=$HOMELAB_REPO/scripts/backup-excludes.conf
VZ_TMP=/var/lib/vz/tmp-backup     # vzdump suspend-mode staging, emptied after each guest

log_to "$HOMELAB_LOG_DIR/backup-offsite.log"
trap finish EXIT
acquire_lock

set -a; source "$ENV_FILE"; set +a
mkdir -p "$VZ_TMP"

if ! restic cat config >/dev/null; then
    fail "restic repository $RESTIC_REPOSITORY is unreachable (is CT 301 up and rclone authorised?)"
    exit 1
fi

excludes_for() { # vzdump --exclude-path args for a vmid ('*' = every guest)
    [[ -f $EXCLUDES ]] || return 0
    awk -v id="$1" '!/^#/ && NF==2 && ($1==id || $1=="*") {print "--exclude-path"; print $2}' "$EXCLUDES"
}

backup_ct() {
    local id=$1 name start
    name=$(pct config "$id" | awk '/^hostname:/ {print $2}')
    mapfile -t excl < <(excludes_for "$id")
    start=$SECONDS
    log "-- $id $name"
    if restic backup --host "$(hostname)" --tag ct --tag "ct-$id" --tag "$name" \
            --stdin-from-command --stdin-filename "ct-$id-$name.tar" -- \
            vzdump "$id" --stdout --compress 0 --mode suspend --tmpdir "$VZ_TMP" "${excl[@]}"; then
        log "   $id $name ok in $(( SECONDS - start ))s"
    else
        fail "$id $name: backup failed"
    fi
    rm -rf "${VZ_TMP:?}"/*
    unlock_stale
}

# An interrupted vzdump can leave a guest with `lock: backup`, which blocks
# start/stop/config changes. Runs after each guest and from finish().
unlock_stale() {
    pgrep -x vzdump >/dev/null && sleep 5
    pgrep -x vzdump >/dev/null && return 0   # a vzdump still owns the lock
    local f id
    for f in /etc/pve/lxc/*.conf; do
        id=$(basename "$f" .conf)
        if grep -q '^lock: backup' "$f"; then
            pct unlock "$id" && warn "CT $id was left locked by vzdump; unlocked"
        fi
    done
}
cleanup_hook() { unlock_stale; rm -rf "${VZ_TMP:?}"/*; }

backup_host_config() {
    log "-- host config"
    restic backup --host "$(hostname)" --tag host-config \
        --exclude /etc/pve/.rrd --exclude /etc/pve/.clusterlog \
        /etc /root/homelab /root/.ssh /var/spool/cron \
        || fail "host config backup failed"
}

if (( $# )); then
    for id in "$@"; do backup_ct "$id"; done
else
    # 301 is the backup gateway itself: backing it up through itself would
    # freeze the server mid-upload, and it holds only credentials that are
    # re-created from docs/backup.md (rebuild, re-authorise Drive).
    while read -r id; do backup_ct "$id"; done < <(pct list | awk 'NR>1 && $1!=301 {print $1}')
    backup_host_config
fi

restic snapshots --latest 1 --compact --host "$(hostname)" | tail -n +1
