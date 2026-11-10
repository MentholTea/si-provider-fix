#!/system/bin/sh
# Module removal: stop every process this module started and drop the exported snapshot.
LOG=/data/local/tmp/si-provider-fix.log

for f in /data/local/tmp/si-provider-fix.watchdog.pid \
         /data/local/tmp/si-provider-fix.pid \
         /data/local/tmp/si-provider-fix.inotifyd.pid; do
    pid=$(cat "$f" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
    fi
    rm -f "$f"
done

# belt and braces: kill any stragglers by cmdline
pkill -f "si-provider-fix/watcher.sh" 2>/dev/null
pkill -f "si-provider-fix/push_rules.sh" 2>/dev/null
pkill -f "inotifyd /data/local/tmp/si-provider-fix.trigger" 2>/dev/null

rm -f /data/local/tmp/si-provider-fix.trigger
rm -f /data/local/tmp/si-provider-fix.lock
rm -f /data/local/tmp/si-provider-fix-rules.json
rm -f /data/local/tmp/si_provider_rules.json
rm -f /data/user_de/0/com.android.providers.media.module/files/si_provider_rules.json
rm -f /data/user_de/0/com.android.providers.media.module/files/si_provider_rules.json.tmp
rm -rf /data/media/0/Android/media/.si_provider_fix
echo "$(date '+%m-%d %H:%M:%S') uninstalled" >> "$LOG"
exit 0
