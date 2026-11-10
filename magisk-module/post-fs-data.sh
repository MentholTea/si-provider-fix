#!/system/bin/sh
# Runs before zygote starts: nothing to do here yet, the daemon needs /data/media which only
# appears after first unlock. Kept for module-manager compatibility.
MODDIR=${0%/*}
exit 0
