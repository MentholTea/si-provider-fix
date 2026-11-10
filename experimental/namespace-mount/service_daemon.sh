#!/system/bin/sh
# Maintain bind mounts inside MediaProvider's mount namespace.
#
# Why this works: MediaProvider has its own mount namespace (verified: its ns inode differs
# from init's), so a bind mount performed there redirects only that process. Writes that arrive
# through MediaStore then land in the configured export target, exactly like Storage Isolation
# does for the app's own namespace.
#
# The namespace is recreated whenever MediaProvider restarts, so this loop watches the pid and
# rebuilds the whole mount set on every change. It also rebuilds when the rule list changes.

MODDIR=${0%/*}
LOG=/data/local/tmp/si-provider-nsmount.log

CONFIG=/data/adb/storage-isolation/configuration.json
EXTRACT="$MODDIR/extract_pairs.sh"

MEDIA_PKG=com.android.providers.media.module
EMULATED=/storage/emulated/0

POLL=2

log() {
    echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG"
    lines=$(wc -l < "$LOG" 2>/dev/null || echo 0)
    if [ "$lines" -gt 500 ]; then
        tail -n 250 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"
    fi
}

# ---------------------------------------------------------------- mount bookkeeping
# Applied mounts are tracked as "src<TAB>dst" lines so they can be unmounted precisely.
STATE_MOUNTS=/data/local/tmp/si-provider-nsmount.applied

clear_mounts() {
    pid=$1
    [ -z "$pid" ] && return
    [ -f "$STATE_MOUNTS" ] || return
    while IFS='	' read -r src dst; do
        [ -z "$dst" ] && continue
        nsenter -t "$pid" -m -- umount "$EMULATED/$dst" 2>/dev/null
    done < "$STATE_MOUNTS"
    rm -f "$STATE_MOUNTS"
}

apply_rules() {
    pid=$1
    : > "$STATE_MOUNTS"

    sh "$EXTRACT" "$CONFIG" > /data/local/tmp/si-provider-nsmount.pairs 2>/dev/null || return 1
    [ -s /data/local/tmp/si-provider-nsmount.pairs ] || return 1

    count=0
    while IFS='	' read -r src dst; do
        [ -z "$src" ] && continue
        [ -z "$dst" ] && continue

        SRC_PATH="$EMULATED/$dst"     # where the file should land
        DST_PATH="$EMULATED/$src"     # the path MediaStore thinks it is writing

        # both must exist, otherwise the rule is meaningless for this provider
        nsenter -t "$pid" -m -- test -d "$SRC_PATH" 2>/dev/null || continue
        nsenter -t "$pid" -m -- test -d "$DST_PATH" 2>/dev/null || continue

        nsenter -t "$pid" -m -- mount --bind "$SRC_PATH" "$DST_PATH" 2>/dev/null
        if [ $? -eq 0 ]; then
            printf '%s\t%s\n' "$src" "$dst" >> "$STATE_MOUNTS"
            count=$((count + 1))
        fi
    done < /data/local/tmp/si-provider-nsmount.pairs

    log "applied $count mounts on pid=$pid"
    return 0
}

rules_fingerprint() {
    [ -f "$CONFIG" ] || { echo "none"; return; }
    stat -c '%s:%Y' "$CONFIG" 2>/dev/null
}

# ---------------------------------------------------------------- main loop
log "daemon start pid=$$"

CUR_PID=""
CUR_RULES=""
TICK=0

while true; do
    PID=$(pidof "$MEDIA_PKG" 2>/dev/null | awk '{print $1}')
    RULES=$(rules_fingerprint)

    if [ -n "$PID" ]; then
        # provider restarted -> its namespace is gone, nothing to unmount
        if [ "$PID" != "$CUR_PID" ]; then
            if [ -n "$CUR_PID" ]; then
                log "provider pid changed $CUR_PID -> $PID, rebuilding"
            else
                log "provider found pid=$PID"
            fi
            rm -f "$STATE_MOUNTS"
            CUR_PID="$PID"
            CUR_RULES=""
        fi

        # rules edited -> drop the old mounts and rebuild
        if [ "$RULES" != "$CUR_RULES" ]; then
            clear_mounts "$PID"
            if apply_rules "$PID"; then
                CUR_RULES="$RULES"
            fi
        fi

        # self-heal: if a mount disappeared (rare, e.g. lazy unmount) rebuild the set
        TICK=$((TICK + 1))
        if [ $((TICK % 30)) -eq 0 ] && [ -f "$STATE_MOUNTS" ]; then
            expected=$(wc -l < "$STATE_MOUNTS" 2>/dev/null || echo 0)
            actual=$(nsenter -t "$PID" -m -- grep -c " $EMULATED/" /proc/self/mountinfo 2>/dev/null || echo 0)
            if [ "$expected" -gt 0 ] && [ "$actual" -lt "$expected" ]; then
                log "mounts dropped (expected=$expected actual=$actual), rebuilding"
                clear_mounts "$PID"
                CUR_RULES=""
            fi
        fi
    else
        if [ -n "$CUR_PID" ]; then
            log "provider gone"
            CUR_PID=""
            CUR_RULES=""
            rm -f "$STATE_MOUNTS"
        fi
    fi

    sleep $POLL
done
