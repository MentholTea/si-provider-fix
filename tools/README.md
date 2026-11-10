# 诊断与测试脚本

在设备上以 root 运行。

| 脚本 | 用途 |
|---|---|
| `regression_test.sh` | 启动一批关键应用（银行/支付/常用），检查是否有崩溃。验证隔离没有破坏应用。 |
| `verify_isolation.sh` | 对比"存储空间总量"与"应用自己 namespace 能看到的内容"，验证隔离有效性。 |
| `measure_perf.sh` | 测量本模块的 CPU、内存、唤醒次数，并换算日均值。 |

## 快速排查

**重定向不生效**

```bash
# 1. 规则快照是否存在且是新的
su -c "stat -c '%y %s' /data/user_de/0/com.android.providers.media.module/files/si_provider_rules.json"

# 2. 守护进程是否在跑
su -c "ps -A -o PID,PPID,ARGS | grep si-provider-fix"

# 3. 最近日志
su -c "tail -20 /data/local/tmp/si-provider-fix.log"

# 4. 改写是否发生（存一张图后看 marker）
su -c "tail -10 /data/user_de/0/com.android.providers.media.module/files/si-provider-fix.marker"
```

marker 里应该能看到：

```
hook-enter pkg=com.android.providers.media.module
media-provider-install
MediaProvider hooks installed=5
write uid=10358 pkgs=[com.max.xiaoheihe] rel=DCIM/HeyBox data=null rules=9
redirect-rel uid=10358 pkg=com.max.xiaoheihe DCIM/HeyBox -> Pictures/小黑盒/
```

**文件落点不对但记录正确**

检查 Storage Isolation 是否在应用 namespace 里做了挂载：

```bash
su -c "hp=\$(pidof com.max.xiaoheihe); grep HeyBox /proc/\$hp/mountinfo"
```

**相册显示旧位置但文件在新位置**

说明 LSPosed 模块没有生效，回到「重定向不生效」排查。
