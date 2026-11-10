#!/system/bin/sh
# 验证 Storage Isolation 的隔离是否真的生效。
#
# 原理：对比"存储空间总量"与"某个应用在自己 namespace 里能看到的内容"。
# 如果应用能看到的子目录数远少于总量，说明隔离有效。
#
# 用法：su -c "sh verify_isolation.sh"

PKGS="com.tencent.mm com.max.xiaoheihe com.taobao.taobao com.xingin.xhs com.ss.android.ugc.aweme"
EMU=/storage/emulated/0

echo "=== 存储空间总量（未被隔离的视角）==="
for d in Pictures DCIM Download Music Movies; do
    n=$(ls -1 "$EMU/$d" 2>/dev/null | wc -l)
    printf "  %-10s %s\n" "$d" "$n"
done

echo
for pkg in $PKGS; do
    pid=$(pidof "$pkg" 2>/dev/null | awk '{print $1}')
    if [ -z "$pid" ]; then
        echo "== $pkg (未运行)"
        continue
    fi
    echo "== $pkg pid=$pid"
    for d in Pictures DCIM Download; do
        n=$(nsenter -t "$pid" -m -- ls -1 "$EMU/$d" 2>/dev/null | wc -l)
        printf "   看到 %-10s %s\n" "$d" "$n"
    done
    echo "   重定向挂载:"
    grep -E " $EMU/(Pictures|DCIM|Download|Music|Movies)" "/proc/$pid/mountinfo" 2>/dev/null \
        | awk '{print "     " $5 " <- " $4}' | head -6
done
