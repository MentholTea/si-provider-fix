#!/system/bin/sh
# Late-start entry: launch the namespace-mount daemon detached from the boot shell.
MODDIR=${0%/*}
LOG=/data/local/tmp/si-provider-nsmount.log

OLD=$(cat /data/local/tmp/si-provider-nsmount.pid 2>/dev/null)
if [ -n "$OLD" ] && kill -0 "$OLD" 2>/dev/null; then
    kill "$OLD" 2>/dev/null
    sleep 1
fi

rm -f /data/local/tmp/si-provider-nsmount.pid

# nohup + disown: the daemon must not die with Magisk's post-boot shell
nohup sh "$MODDIR/service_daemon.sh" >> "$LOG" 2>&1 &
DAEMON_PID=$!
disown 2>/dev/null

echo "$DAEMON_PID" > /data/local/tmp/si-provider-nsmount.pid
echo "$(date '+%m-%d %H:%M:%S') service.sh started daemon pid=$DAEMON_PID" >> "$LOG"
