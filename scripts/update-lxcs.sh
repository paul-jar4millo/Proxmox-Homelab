#!/usr/bin/env bash
# Update OS packages inside running Debian/Ubuntu containers.
# Each container is backed up with vzdump first, so a bad upgrade can be
# rolled back with `pct restore`. Replaces the community-scripts curl|bash
# cron removed on 2026-09-17.
#
# Usage: update-lxcs.sh [vmid ...]   (no args = every running container)
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

STORAGE=local        # where pre-update backups go
KEEP=2               # backups kept per container on $STORAGE
MIN_FREE_GB=25       # refuse to run if the root filesystem has less than this
LOG=/var/log/homelab/update-lxcs.log

mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1
echo "=== $(date -Is) start"

free_gb=$(( $(df --output=avail -B1 / | tail -1) / 1024**3 ))
if (( free_gb < MIN_FREE_GB )); then
    echo "only ${free_gb} GB free on /, need ${MIN_FREE_GB}; aborting"
    exit 1
fi

if (( $# )); then ids=("$@"); else
    mapfile -t ids < <(pct list | awk 'NR>1 && $2=="running" {print $1}')
fi

for id in "${ids[@]}"; do
    name=$(pct config "$id" | awk '/^hostname:/ {print $2}')
    ostype=$(pct config "$id" | awk '/^ostype:/ {print $2}')
    case "$ostype" in
        debian|ubuntu) ;;
        *) echo "-- $id $name: ostype=$ostype, skipped"; continue ;;
    esac

    echo "-- $id $name: backup"
    if ! vzdump "$id" --storage "$STORAGE" --mode suspend --compress zstd \
            --prune-backups "keep-last=$KEEP" --quiet 1 \
            --notes-template "pre-update {{guestname}}"; then
        echo "-- $id $name: backup FAILED, not updating"
        continue
    fi

    echo "-- $id $name: apt"
    if pct exec "$id" -- env DEBIAN_FRONTEND=noninteractive bash -c '
            apt-get update -q &&
            apt-get dist-upgrade -y -q \
                -o Dpkg::Options::=--force-confdef \
                -o Dpkg::Options::=--force-confold &&
            apt-get autoremove -y -q'; then
        pct exec "$id" -- test -f /var/run/reboot-required \
            && echo "-- $id $name: reboot required" || true
    else
        echo "-- $id $name: apt FAILED"
    fi
done
echo "=== $(date -Is) done"
