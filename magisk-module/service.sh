#!/system/bin/sh
# Late-start entry: bring up the event-driven rule watcher under a watchdog.
#
# Two processes:
#   watcher.sh   owns inotifyd, restarts it if it dies; zero idle CPU
#   watchdog.sh  restarts watcher.sh if the whole thing disappears (LMK, user kill)
#
# The watchdog polls slowly (60s) because losing it for a minute only means that a rule edit
# would not be exported until the next check - not a correctness problem.

MODDIR=${0%/*}
LOG=/data/local/tmp/si-provider-fix.log
PIDFILE=/data/local/tmp/si-provider-fix.pid
WDPID=/data/local/tmp/si-provider-fix.watchdog.pid
IPID=/data/local/tmp/si-provider-fix.inotifyd.pid

for f in "$WDPID" "$PIDFILE" "$IPID"; do
    old=$(cat "$f" 2>/dev/null)
    if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
        kill "$old" 2>/dev/null
        sleep 1
    fi
    rm -f "$f"
done

nohup sh "$MODDIR/watchdog.sh" >> "$LOG" 2>&1 &
WD=$!
disown 2>/dev/null
echo "$WD" > "$WDPID"

echo "$(date '+%m-%d %H:%M:%S') service.sh started watchdog pid=$WD" >> "$LOG"
