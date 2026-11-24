#!/usr/bin/env bash
# Update OS packages inside running Debian/Ubuntu containers.
# Each container is backed up with vzdump first, so a bad upgrade can be
# rolled back with `pct restore`. Replaces the community-scripts curl|bash
# cron removed on 2026-09-17.
#
# After the run it audits every container (running or not) against the
# update policy in docs/update-policy.md and mails a report when something
# failed, a container was skipped, or a guest is on an old OS release.
#
# Usage: update-lxcs.sh [vmid ...]   (no args = every running container)
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"

STORAGE=local        # where pre-update backups go
KEEP=2               # backups kept per container on $STORAGE
MIN_FREE_GB=25       # refuse to run if the root filesystem has less than this
# Releases a guest is expected to run (docs/update-policy.md). Debian follows
# the host's own release; Ubuntu follows the current LTS.
EXPECTED_DEBIAN=$(. /etc/os-release && echo "$VERSION_CODENAME")
EXPECTED_UBUNTU=noble

log_to "$HOMELAB_LOG_DIR/update-lxcs.log"
trap finish EXIT
acquire_lock

free_gb=$(( $(df --output=avail -B1 / | tail -1) / 1024**3 ))
if (( free_gb < MIN_FREE_GB )); then
    fail "only ${free_gb} GB free on /, need ${MIN_FREE_GB}; no container was updated"
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
        *) warn "$id $name: ostype=$ostype is not updated by this script"; continue ;;
    esac

    log "-- $id $name: backup"
    if ! vzdump "$id" --storage "$STORAGE" --mode suspend --compress zstd \
            --prune-backups "keep-last=$KEEP" --quiet 1 \
            --notes-template "pre-update {{guestname}}"; then
        fail "$id $name: pre-update backup failed, container NOT updated"
        continue
    fi

    log "-- $id $name: apt"
    if pct exec "$id" -- env DEBIAN_FRONTEND=noninteractive bash -c '
            apt-get update -q &&
            apt-get dist-upgrade -y -q \
                -o Dpkg::Options::=--force-confdef \
                -o Dpkg::Options::=--force-confold &&
            apt-get autoremove -y -q &&
            apt-get clean'; then
        if pct exec "$id" -- test -f /var/run/reboot-required; then
            warn "$id $name: reboot required"
        fi
    else
        fail "$id $name: apt upgrade failed"
    fi
done

# --- policy audit (docs/update-policy.md) -----------------------------------
log "-- audit"
while read -r id status; do
    name=$(pct config "$id" | awk '/^hostname:/ {print $2}')
    if [[ $status != running ]]; then
        warn "$id $name: $status, so it was not updated this week"
        continue
    fi
    if ! read -r os codename < <(pct exec "$id" -- sh -c \
            '. /etc/os-release; echo "$ID ${VERSION_CODENAME:-unknown}"'); then
        warn "$id $name: could not read /etc/os-release"
        continue
    fi
    pending=$(pct exec "$id" -- sh -c \
        'apt-get -s -o Debug::NoLocking=1 dist-upgrade 2>/dev/null | grep -c ^Inst' || true)
    log "   $id $name: $os $codename, ${pending:-?} packages pending"
    case "$os" in
        debian) [[ $codename == "$EXPECTED_DEBIAN" ]] ||
                    warn "$id $name: Debian $codename, policy is $EXPECTED_DEBIAN (release upgrade needed)" ;;
        ubuntu) [[ $codename == "$EXPECTED_UBUNTU" ]] ||
                    warn "$id $name: Ubuntu $codename, policy is $EXPECTED_UBUNTU (release upgrade needed)" ;;
        *)      warn "$id $name: unknown OS '$os'" ;;
    esac
    (( ${pending:-0} == 0 )) || warn "$id $name: still $pending packages pending after the run"
done < <(pct list | awk 'NR>1 {print $1, $2}')
