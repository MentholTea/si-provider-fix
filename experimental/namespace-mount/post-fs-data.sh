#!/system/bin/sh
# Runs before zygote starts. Nothing to do: the target namespace only exists once
# MediaProvider is alive, which happens after boot.
MODDIR=${0%/*}
exit 0
