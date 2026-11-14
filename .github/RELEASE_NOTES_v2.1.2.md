# v2.1.2

阻止 MediaProvider 在共享存储根目录创建多余文件夹。

## 变更

- 新增 native 层 `lib/arm64-v8a/libmishareguard.so`，inline hook libc 的 `mkdirat` / `mkdir`
- 拦截根目录下的 `MiShare` 与 `com.miui.voiceassist`
- 只匹配 `<root><name>` 或 `<root><name>/`，`Download/MiShare` 与任意子路径不受影响
- versionCode 23

## 背景

MediaProvider 每次进程启动都会创建 `/storage/emulated/0/MiShare`（空壳，互传实际写
`Download/MiShare`）。strace 显示调用来自 FUSE worker 线程的 `mkdirat(..., 0775)`，在 Java
层之下，`File.mkdirs` / `Os.mkdir` / `libcore.io.Linux.mkdir` 全部命中不了，因此改为 native 拦截。
`com.miui.voiceassist` 是语音助手创建的 `audio/` 空壳，非每次必建，一并加入名单。

## 安装

1. `adb install -r si-provider-fix.apk`
2. LSPosed 中启用模块，作用域勾选「媒体存储」与「Storage Isolation」
3. 重启

## 校验

```
d26af6b7d8d825033572ccee0f6ba5ce6c0387265040124cbb3e52a5ecb14b9c  si-provider-fix.apk
b1fd59d1f1119616015efe3ea7799a7c5efb27109bcefc479be3a101ebaef550  si-provider-fix-magisk.zip
```
