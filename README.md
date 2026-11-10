# SI Provider Fix

让 **Storage Isolation（储存空间隔离）** 的「处理系统提供程序」在 Android 17 上重新工作。

> 原版增强模块 `zygisk-storage-isolation` 的这部分功能在 Android 17 上失效，导致应用通过 MediaStore 保存的图片
> 仍然落在被隔离前的原始目录（例如 `DCIM/HeyBox`），而不是导出规则配置的目标目录（例如 `Pictures/小黑盒`）。
> 本项目是一个替代实现。

---

## 问题是什么

Storage Isolation 的工作方式是在**应用自己的 mount namespace** 里做 bind mount：

```
应用进程内:  /storage/emulated/0/DCIM/HeyBox  →  /media/0/Pictures/小黑盒
```

所以应用直接用文件路径写 `DCIM/HeyBox/xxx.jpg` 时，文件确实会落到 `Pictures/小黑盒`。

问题出在**走 MediaStore 的写入**：

1. 应用调用 `ContentResolver.insert(MediaStore.Images..., relative_path="DCIM/HeyBox/")`
2. 请求被发到 **MediaProvider 进程**
3. MediaProvider 在**它自己的 namespace** 里解析这个相对路径
4. 该 namespace 没有 Storage Isolation 的挂载，所以文件落在真实的 `DCIM/HeyBox`
5. MediaStore 记录 `relative_path = DCIM/HeyBox/`，相册据此显示"旧位置"

原版模块设计上通过替换 `ServiceManager.sServiceManager` 为动态代理来拦截 provider 发布，从而改写路径。
Android 17 上这条反射路径被 hidden-API 策略挡住，`install()` 抛异常后**静默失败**，功能整体失效。

## 本项目怎么修

两处组件，各司其职：

| 组件 | 载体 | 职责 |
|---|---|---|
| **magisk-module** | Magisk / KernelSU 模块（纯 shell） | 监听 Storage Isolation 配置变化，把导出规则导出成 MediaProvider 可读的快照 |
| **lsposed-module** | LSPosed 模块（Java） | 注入 MediaProvider，在写入前按规则改写 `relative_path` |

数据流：

```
/data/adb/storage-isolation/configuration.json      (root only)
        │
        │  inotify 监听 + extract_rules.sh 解析
        ▼
/data/user_de/0/com.android.providers.media.module/files/si_provider_rules.json
        │
        │  LSPosed 模块读取（2 秒缓存）
        ▼
MediaProvider.insert()  →  改写 relative_path  →  写入 external.db
        │
        ▼
相册显示正确位置 + 文件落在导出目标
```

### 为什么不用 namespace 挂载

我们试过在 MediaProvider 的 namespace 里直接 `mount --bind`（见 `experimental/`）。
文件落点是正确的，但 **MediaStore 的记录仍然是旧路径**，因为应用上报的就是旧路径，
而 `_data` / `relative_path` 是只读列，无法事后修正。只有 Java 层在写入前改写才能彻底解决。

---

## 安装

### 前置

- Android 13+（在 Android 17 / HyperOS 3 上验证）
- KernelSU 或 Magisk（需要 root）
- Zygisk 已启用（`zygisksu` / Zygisk Next）
- LSPosed 2.x
- Storage Isolation v8.8.x

### 步骤

1. **安装 Magisk 模块**

   ```bash
   adb push prebuilt/si-provider-fix-magisk.zip /data/local/tmp/
   adb shell su -c "ksud module install /data/local/tmp/si-provider-fix-magisk.zip"
   # Magisk 用户：直接在管理器里刷入 zip
   ```

2. **安装 LSPosed 模块**

   ```bash
   adb install -r prebuilt/si-provider-fix.apk
   ```

3. **在 LSPosed 管理器里启用并勾选作用域**

   模块名：`SI Provider Fix`

   作用域必须勾选：
   - `媒体存储` / `com.android.providers.media.module`
   - `Storage Isolation` / `moe.shizuku.redirectstorage`

4. **重启**

5. **验证**

   ```bash
   # 规则快照是否生成
   su -c "cat /data/user_de/0/com.android.providers.media.module/files/si_provider_rules.json"

   # 守护进程是否在跑
   su -c "ps -A -o PID,ARGS | grep si-provider-fix"

   # 改写是否发生（存一张图后看）
   su -c "cat /data/user_de/0/com.android.providers.media.module/files/si-provider-fix.marker"
   ```

---

## 工作细节

### Magisk 模块

```
service.sh     开机启动 watchdog
watchdog.sh    每 60 秒检查 watcher 是否存活
watcher.sh     管理 inotifyd，事件驱动
  └── inotifyd 监听 /data/adb/storage-isolation (cwenmd)
        └── push_rules.sh  解析配置、原子写入快照
```

**零空闲轮询**：`inotifyd` 阻塞等待文件事件，只有 Storage Isolation 真的写配置时才唤醒。
实测日均唤醒 14,400 次、CPU 2.9 秒（对比 3 秒轮询方案的 145,440 次 / 60.5 秒，降低 90%+）。

**几个踩过的坑**（都在代码注释里）：

- toybox 的 `inotifyd` 掩码必须写成 `cwenmd`，逗号分隔会报 `bad mask ','`
- 监听**目录**而不是文件：配置若以 rename 方式保存，文件监听会收到 DELETE 后退出
- 快照用「临时文件 + rename」原子替换，避免 MediaProvider 读到半截 JSON
- `push_rules.sh` 用 `mkdir` 锁防止事件风暴并发推送

### LSPosed 模块

Hook 的入口（`MediaProviderHooks`）：

```java
MediaProvider.insert(Uri, ContentValues)
MediaProvider.insert(Uri, ContentValues, Bundle)
MediaProvider.bulkInsert(Uri, ContentValues[])
MediaProvider.update(Uri, ContentValues, String, String[])
MediaProvider.update(Uri, ContentValues, Bundle)
```

每次写入前：

1. `Binder.getCallingUid()` → `PackageManager.getPackagesForUid()` 得到调用方包名
2. 查规则表，匹配 `relative_path` 的 `source` 前缀
3. 命中则改写为 `target`，然后放行

规则表由 `RuleStore` 维护，**2 秒 TTL**，只读 DE 目录那一个文件。

---

## 构建

### LSPosed 模块

需要 JDK 17+、Android SDK（build-tools 34+、platform 35）。

```powershell
cd lsposed-module
pwsh -File build.ps1
```

脚本会：编译 Xposed 桩 → 编译模块 → d8 转 dex → aapt2 打包 → zipalign → 签名。

> 注意：项目路径含非 ASCII 字符时 aapt2 会失败，`build.ps1` 已自动镜像到 `%TEMP%` 的 ASCII 目录再构建。

### Magisk 模块

纯 shell，直接打包：

```bash
cd magisk-module
zip -r ../si-provider-fix-magisk.zip .
```

---

## 已验证环境

| 项目 | 版本 |
|---|---|
| 设备 | Xiaomi 2509FPN0BC |
| 系统 | HyperOS 3 / Android 17 (SDK 37) |
| 内核 | 6.12.69-android16 |
| Root | KernelSU |
| Zygisk | Zygisk Next 1.5.3 |
| LSPosed | 2.2.1 (7940) |
| Storage Isolation | 8.8.1.r3684 |

---

## 已知限制

- **只覆盖 MediaProvider**。`DownloadProvider`（`android.process.media`）未覆盖。
  实测 MediaStore 中 `Download/` 路径的记录为 0 条，普通下载不进入相册，所以暂未处理。
- **不支持多用户**。规则快照是单份，多用户场景需要扩展。
- **依赖 root**。`configuration.json` 仅 root 可读，MediaProvider 不在 KernelSU 允许列表内，无法自己拉取。

---

## 目录

```
magisk-module/         Magisk 模块（正式）
lsposed-module/        LSPosed 模块源码与构建脚本
prebuilt/              预编译产物
tools/                 诊断与回归测试脚本
experimental/          已废弃的 namespace 挂载方案（保留供参考）
```

---

## License

MIT
