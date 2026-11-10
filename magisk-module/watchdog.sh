#!/system/bin/sh
# Supervise the event-driven watcher.
#
# Polls slowly: the watcher itself has no idle cost, so this loop only needs to notice the rare
# case where the watcher (or its inotifyd child) is gone.

MODDIR=${0%/*}
LOG=/data/local/tmp/si-provider-fix.log
PIDFILE=/data/local/tmp/si-provider-fix.pid
CHECK_INTERVAL=60

log() {
    echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG"
    lines=$(wc -l < "$LOG" 2>/dev/null || echo 0)
    if [ "$lines" -gt 400 ]; then
        tail -n 200 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"
    fi
}

alive() {
    pid="$1"
    [ -n "$pid" ] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
    case "$cmdline" in
        *watcher.sh*) return 0 ;;
        *) return 1 ;;
    esac
}

log "watchdog start pid=$$"

while true; do
    pid=$(cat "$PIDFILE" 2>/dev/null)
    if ! alive "$pid"; then
        log "watcher not alive (pid=$pid), restarting"
        nohup sh "$MODDIR/watcher.sh" >> "$LOG" 2>&1 &
        newpid=$!
        disown 2>/dev/null
        echo "$newpid" > "$PIDFILE"
        log "watchdog restarted watcher pid=$newpid"
    fi
    sleep $CHECK_INTERVAL
done
