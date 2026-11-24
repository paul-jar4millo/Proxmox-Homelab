#!/usr/bin/env bash
# Weekly backup maintenance (Sunday). Runs from the host so every failure is
# mailed through the same path as the other jobs.
#
#   1. retention + prune     inside CT 301, the only place with a key that may
#                            delete (the host's REST access is append-only)
#   2. integrity check       restic check, reading a random 5 % of the data
#   3. freshness             every guest and the host config must have a
#                            snapshot younger than MAX_AGE_H
#   4. restore drill         first Sunday of the month: restore a real
#                            container from Drive and boot it (restore-drill.sh)
#   5. weekly report         one mail with the numbers, even when all is well,
#                            so silence itself is a signal
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"

ENV_FILE=/root/.config/restic/homelab.env
MAX_AGE_H=36
DRILL_VMID=202     # small, self-contained; restored as 9<vmid> without network

log_to "$HOMELAB_LOG_DIR/backup-maintenance.log"
trap finish EXIT
acquire_lock

set -a; source "$ENV_FILE"; set +a
report=$(mktemp)
trap 'rc=$?; rm -f "$report" "$report.maint"; (exit $rc); finish' EXIT

log "-- forget/prune/check in CT 301"
if ! pct exec 301 -- runuser -u rclone -- /usr/local/bin/restic-maint >"$report.maint" 2>&1; then
    fail "restic-maint in CT 301 failed"
fi
cat "$report.maint"

log "-- freshness"
now=$(date +%s)
snapjson=$(restic snapshots --host "$(hostname)" --json)
expect=$(pct list | awk 'NR>1 && $1!=301 {print "ct-"$1}'; echo host-config)
for tag in $expect; do
    last=$(jq -r --arg t "$tag" '[.[] | select(.tags | index($t)) | .time] | max // empty' <<<"$snapjson")
    if [[ -z $last ]]; then
        fail "$tag has no snapshot at all"; continue
    fi
    age_h=$(( (now - $(date -d "$last" +%s)) / 3600 ))
    printf '%-14s last %s (%sh ago)\n' "$tag" "${last%%.*}" "$age_h" >>"$report"
    (( age_h <= MAX_AGE_H )) || fail "$tag: newest snapshot is ${age_h}h old (limit ${MAX_AGE_H}h)"
done

if (( $(date +%-d) <= 7 )); then
    log "-- monthly restore drill"
    if "$HOMELAB_REPO/scripts/restore-drill.sh" "$DRILL_VMID" >>"$report" 2>&1; then
        log "   drill ok"
    else
        fail "monthly restore drill of CT $DRILL_VMID failed"
    fi
fi

summary=$(
    echo "Weekly backup report for $(hostname), $(date '+%F %R')"
    echo
    echo "Snapshots per guest:"; cat "$report"
    echo
    echo "Repository (from CT 301):"
    grep -E 'Total|snapshots|keep|remove|no errors|error' "$report.maint" || true
)
rm -f "$report.maint"
echo "$summary"
# On failure finish() mails the errors plus this log; on success send the
# report itself as the weekly proof of life.
(( ${#FAILURES[@]} )) || notify "backup weekly report: OK" <<<"$summary"
