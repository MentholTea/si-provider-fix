#!/system/bin/sh
# Stop the daemon and unmount everything it installed.
LOG=/data/local/tmp/si-provider-nsmount.log
STATE=/data/local/tmp/si-provider-nsmount.applied
EMULATED=/storage/emulated/0
MEDIA_PKG=com.android.providers.media.module

PID=$(cat /data/local/tmp/si-provider-nsmount.pid 2>/dev/null)
if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null
fi

MP=$(pidof "$MEDIA_PKG" 2>/dev/null | awk '{print $1}')
if [ -n "$MP" ] && [ -f "$STATE" ]; then
    while IFS='	' read -r src dst; do
        [ -z "$dst" ] && continue
        nsenter -t "$MP" -m -- umount "$EMULATED/$dst" 2>/dev/null
    done < "$STATE"
fi

rm -f /data/local/tmp/si-provider-nsmount.pid
rm -f "$STATE"
rm -f /data/local/tmp/si-provider-nsmount.pairs
echo "$(date '+%m-%d %H:%M:%S') uninstalled" >> "$LOG"
exit 0
