#!/system/bin/sh
# 隔离回归测试：验证 Storage Isolation 没有破坏关键应用。
#
# 用法（在设备上以 root 运行）：
#   su -c "sh regression_test.sh"
#
# 对每个高风险管理类应用：force-stop → 启动 → 检查进程是否存活。
# 结果写入 /data/local/tmp/isolation-regression.log

LOG=/data/local/tmp/isolation-regression.log
: > "$LOG"

# 银行、支付、系统类：这些应用最能暴露隔离副作用
HIGH_RISK="
com.android.bankabc
com.chinamworld.main
com.cgbchina.xpt
com.unionpay
com.hexin.plat.android
com.eg.android.AlipayGphone
com.tencent.mm
com.taobao.taobao
com.tencent.mobileqq
"

# 常用应用
NORMAL="
com.xingin.xhs
com.max.xiaoheihe
com.netease.cloudmusic
cn.kuwo.player
com.baidu.netdisk
com.deepseek.chat
com.openai.chatgpt
tv.danmaku.bili
com.zhihu.android
"

log() { echo "$*" | tee -a "$LOG"; }

test_pkg() {
    pkg="$1"
    act=$(cmd package resolve-activity --brief "$pkg" 2>/dev/null | tail -1)
    if [ -z "$act" ] || [ "$act" = "No activity found" ]; then
        log "SKIP  $pkg  (无启动入口或未安装)"
        return
    fi

    am force-stop "$pkg" 2>/dev/null
    sleep 1
    am start -W -n "$act" >/dev/null 2>&1
    rc=$?
    sleep 4

    pid=$(pidof "$pkg" 2>/dev/null | awk '{print $1}')
    if [ -n "$pid" ]; then
        log "PASS  $pkg  pid=$pid"
        am force-stop "$pkg" 2>/dev/null
        return
    fi

    reason=$(dumpsys activity exit-info "$pkg" 2>/dev/null \
        | grep -m1 -A1 "timestamp=" | tr '\n' ' ')
    log "FAIL  $pkg  rc=$rc  $reason"
}

log "=== 隔离回归测试 $(date '+%m-%d %H:%M:%S') ==="
log ""
log "--- 高风险管理类 ---"
for p in $HIGH_RISK; do test_pkg "$p"; done
log ""
log "--- 常用应用 ---"
for p in $NORMAL; do test_pkg "$p"; done

log ""
log "--- crash buffer (最后 30 行) ---"
logcat -d -b crash -t 30 2>/dev/null | tee -a "$LOG"

log ""
log "=== 完成 ==="
