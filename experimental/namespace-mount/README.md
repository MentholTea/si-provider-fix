# 实验性方案：MediaProvider namespace 挂载

**状态：已废弃，保留供参考。**

## 思路

MediaProvider 有自己的 mount namespace：

```
init : mnt:[4026532903]
MP   : mnt:[4026536481]     ← 每次重启重建
```

所以在它的 namespace 里直接 bind mount 就能重定向写入：

```bash
MP=$(pidof com.android.providers.media.module)
nsenter -t $MP -m -- mount --bind \
    /storage/emulated/0/Pictures/小黑盒 \
    /storage/emulated/0/DCIM/HeyBox
```

## 实测结果

**文件落点：正确** ✓

通过 MP namespace 写入 `DCIM/HeyBox/probe.txt`，文件实际落在
`/data/media/0/Pictures/小黑盒/`（底层验证，绕过 FUSE）。

**MediaStore 记录：错误** ✗

```
_id=82657  _data=/storage/emulated/0/DCIM/HeyBox/78d95e9f....webp
           relative_path=DCIM/HeyBox/
```

记录仍指向旧路径，相册据此显示"旧位置"。

## 为什么不可行

挂载对应用是**透明**的：应用不知道自己被重定向，仍然按 `DCIM/HeyBox/xxx` 上报路径。
而 `_data` / `relative_path` 是只读列：

```bash
content update --uri content://media/external/images/media/82657 \
    --bind _data:s:/storage/emulated/0/Pictures/小黑盒/...   # 被忽略，无报错
```

Android 10+ 强制此设计。所以事后修正不可能，必须在**写入数据库之前**改写 —— 这需要 Java 层 hook。

## 保留的文件

| 文件 | 作用 |
|---|---|
| `extract_pairs.sh` | 从 configuration.json 提取 `source<TAB>target` 对 |
| `service_daemon.sh` | 轮询 MediaProvider pid 与配置，维护 namespace 挂载 |
| `service.sh` | 开机启动 |
| `uninstall.sh` | 卸载所有挂载 |

## 什么情况下仍有价值

如果将来出现"只需要文件落点正确、不关心 MediaStore 记录"的场景（例如某个应用
写文件后自己管理索引，不依赖 MediaStore），这个方案更轻：纯 shell，不需要 LSPosed。

另外它天然覆盖 `DownloadProvider`（如果那个进程也有独立 namespace），
而当前的 Java 方案只管 MediaProvider。
