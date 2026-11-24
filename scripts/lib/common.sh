# Shared helpers for the homelab maintenance scripts. Source, don't execute.
#
#   log_to FILE      send the rest of the script's output to FILE only, so cron
#                    mails nothing unless the script dies before this line
#   acquire_lock     one maintenance job at a time (vzdump, apt, restic)
#   notify SUBJECT   mail stdin to root; proxmox-mail-forward hands it to the
#                    Proxmox notification system, which routes it to Gmail
#   fail MSG         record a failure; finish() turns failures into a mail
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export LC_ALL=C.UTF-8

HOMELAB_REPO=/root/homelab
HOMELAB_LOG_DIR=/var/log/homelab
HOMELAB_LOCK=/run/lock/homelab-jobs.lock
JOB_NAME=$(basename "$0" .sh)
FAILURES=()
WARNINGS=()

log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }

log_to() {
    mkdir -p "$(dirname "$1")"
    JOB_LOG=$1
    exec >>"$JOB_LOG" 2>&1
    log "=== $JOB_NAME start (pid $$)"
}

acquire_lock() {
    exec 9>"$HOMELAB_LOCK"
    if ! flock -w "${1:-10800}" 9; then
        fail "could not acquire $HOMELAB_LOCK within ${1:-10800}s"
        exit 1
    fi
}

notify() {
    local subject=$1
    { printf 'To: root\nSubject: [homelab] %s\nContent-Type: text/plain; charset=UTF-8\n\n' "$subject"
      cat
    } | /usr/sbin/sendmail -t
}

fail() { FAILURES+=("$*"); log "FAIL: $*"; }

# A job killed by systemd, shutdown or Ctrl-C is a failure, never a success.
on_signal() { fail "terminated by SIG$1 before finishing"; exit 1; }
trap 'on_signal TERM' TERM
trap 'on_signal INT' INT
trap 'on_signal HUP' HUP
warn() { WARNINGS+=("$*"); log "WARN: $*"; }

# Mails a report when anything failed or warned, or when the script died
# early (set -e). Call as: trap finish EXIT
finish() {
    local rc=$?
    # scripts may define cleanup_hook to undo partial work (e.g. vzdump locks)
    if declare -F cleanup_hook >/dev/null; then cleanup_hook || true; fi
    (( rc != 0 && ${#FAILURES[@]} == 0 )) && FAILURES+=("exited with status $rc (see log)")
    log "=== $JOB_NAME end rc=$rc failures=${#FAILURES[@]} warnings=${#WARNINGS[@]}"
    if (( ${#FAILURES[@]} || ${#WARNINGS[@]} )); then
        local level=WARNING
        (( ${#FAILURES[@]} )) && level=ERROR
        {
            echo "Job: $JOB_NAME on $(hostname) at $(date -Is)"
            echo
            for f in "${FAILURES[@]}"; do echo "ERROR: $f"; done
            for w in "${WARNINGS[@]}"; do echo "WARN:  $w"; done
            echo
            echo "--- last 40 log lines (${JOB_LOG:-no log}) ---"
            [[ -n ${JOB_LOG:-} ]] && tail -n 40 "$JOB_LOG"
        } | notify "$level: $JOB_NAME"
    fi
    (( ${#FAILURES[@]} == 0 )) || exit 1
}
