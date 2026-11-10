#!/system/bin/sh
# 测量本模块的运行开销。
#
# 用法：su -c "sh measure_perf.sh"
#
# 输出：各进程的 CPU 占用、内存、唤醒次数；以及换算成日均值。

HZ=100
UP=$(awk '{print $1}' /proc/uptime)
echo "系统已运行: ${UP}s"
echo

report() {
    label="$1"
    pid="$2"
    [ -z "$pid" ] && return
    [ -d "/proc/$pid" ] || return
    ticks=$(awk '{print $14+$15}' "/proc/$pid/stat" 2>/dev/null)
    [ -z "$ticks" ] && return
    secs=$(awk -v t="$ticks" -v h="$HZ" 'BEGIN{printf "%.2f", t/h}')
    pct=$(awk -v t="$ticks" -v h="$HZ" -v u="$UP" \
        'BEGIN{if(u>0) printf "%.4f", (t/h)/u*100; else print "0"}')
    rss=$(awk '/VmRSS/{print $2}' "/proc/$pid/status" 2>/dev/null)
    echo "$label pid=$pid cpu=${secs}s lifetime=${pct}% rss=${rss:-0}KB"
}

echo "=== 本模块 ==="
report "watchdog  " $(cat /data/local/tmp/si-provider-fix.watchdog.pid 2>/dev/null)
report "watcher   " $(cat /data/local/tmp/si-provider-fix.pid 2>/dev/null)
report "inotifyd  " $(cat /data/local/tmp/si-provider-fix.inotifyd.pid 2>/dev/null)

echo
echo "=== Storage Isolation ==="
report "si_daemon " $(pidof storage_isolation_daemon | awk '{print $1}')
report "si_server " $(pidof storage_isolation | awk '{print $1}')

echo
echo "=== MediaProvider（LSPosed hook 所在进程）==="
report "mediaprov " $(pidof com.android.providers.media.module | awk '{print $1}')

echo
echo "=== 60 秒实测（唤醒数与 CPU 增量）==="
W=$(cat /data/local/tmp/si-provider-fix.watchdog.pid 2>/dev/null)
I=$(cat /data/local/tmp/si-provider-fix.inotifyd.pid 2>/dev/null)
if [ -n "$W" ] && [ -n "$I" ]; then
    wa=$(awk '/^voluntary_ctxt_switches/{print $2}' /proc/$W/status)
    ia=$(awk '/^voluntary_ctxt_switches/{print $2}' /proc/$I/status)
    ca=$(awk '{print $14+$15}' /proc/$W/stat)
    cb=$(awk '{print $14+$15}' /proc/$I/stat)
    sleep 60
    wb=$(awk '/^voluntary_ctxt_switches/{print $2}' /proc/$W/status)
    ib=$(awk '/^voluntary_ctxt_switches/{print $2}' /proc/$I/status)
    cd=$(awk '{print $14+$15}' /proc/$W/stat)
    ce=$(awk '{print $14+$15}' /proc/$I/stat)
    awk -v x=$((wb-wa+ib-ia)) -v y=$((cd-ca+ce-cb)) \
        'BEGIN{printf "  唤醒 %d 次 -> 日均 %d\n  CPU %d ticks -> 日均 %.1f 秒\n", x, x*1440, y, y/100/60*86400}'
else
    echo "  进程未运行，跳过"
fi
