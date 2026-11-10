#!/system/bin/sh
# Push Storage Isolation's export rules to a snapshot MediaProvider can read.
#
# Runs on demand: either triggered by inotifyd when the configuration changes, or once at
# startup. Exits quickly; it holds no state and can be called as often as needed.
#
# Kept atomic: the snapshot is written to a temp file then renamed, so MediaProvider never
# observes a half-written JSON document.

MODDIR=${0%/*}
LOG=/data/local/tmp/si-provider-fix.log

CONFIG=/data/adb/storage-isolation/configuration.json
RULES_DE=/data/user_de/0/com.android.providers.media.module/files/si_provider_rules.json
RULES_DE_DIR=$(dirname "$RULES_DE")
STAGING=/data/local/tmp/si-provider-fix-rules.json
TMP=$RULES_DE.tmp
MP_UID=10282

log() {
    echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG"
}

[ -f "$CONFIG" ] || { log "push: config missing"; exit 1; }

# guard against concurrent pushes triggered by a burst of inotify events
LOCK=/data/local/tmp/si-provider-fix.lock
if ! mkdir "$LOCK" 2>/dev/null; then
    exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

if ! sh "$MODDIR/extract_rules.sh" "$CONFIG" "$STAGING" >> "$LOG" 2>&1; then
    log "push: extract failed"
    exit 1
fi

mkdir -p "$RULES_DE_DIR" 2>/dev/null

# atomic replace: write temp in the same directory, then rename over the target
if ! cp -f "$STAGING" "$TMP" 2>/dev/null; then
    log "push: staging copy failed"
    rm -f "$TMP"
    exit 1
fi
chown $MP_UID:$MP_UID "$TMP" 2>/dev/null
chmod 644 "$TMP" 2>/dev/null

if ! mv -f "$TMP" "$RULES_DE" 2>/dev/null; then
    log "push: rename failed"
    rm -f "$TMP"
    exit 1
fi

COUNT=$(grep -o '"pkg"' "$STAGING" 2>/dev/null | wc -l)
log "pushed rules=$COUNT"
exit 0
