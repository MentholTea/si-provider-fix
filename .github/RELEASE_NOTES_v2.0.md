# v2.0

让 **Storage Isolation（储存空间隔离）** 的「处理系统提供程序」在 Android 17 上重新工作。

## 这个版本修复了什么

原版增强模块 `zygisk-storage-isolation` 的「处理系统提供程序」在 Android 17 上失效，导致：

- 应用通过 MediaStore 保存的图片仍落在隔离前的原始目录（如 `DCIM/HeyBox`）
- 而不是导出规则配置的目标目录（如 `Pictures/小黑盒`）
- 相册里显示的位置也是错的

**根因**：原模块的 `u0.install()` 通过反射替换 `ServiceManager.sServiceManager` 为动态代理，
以此拦截 provider 发布。Android 17 上这条路径被 hidden-API 策略拦截，抛异常后静默失败。

## 方案

两处组件协作：

| 组件 | 载体 | 职责 |
|---|---|---|
| `si-provider-fix-magisk.zip` | Magisk / KernelSU 模块 | 监听 SI 配置变化，导出规则快照 |
| `si-provider-fix.apk` | LSPosed 模块 | 注入 MediaProvider，写入前改写 `relative_path` |

**为什么必须在 Java 层改写**：`_data` / `relative_path` 是只读列，写入数据库后无法修正。
只在 MediaProvider 的命名空间里做 bind mount 能让文件落点正确，但 MediaStore 记录仍是旧路径。

## 安装

1. **刷入 Magisk 模块**

   ```bash
   adb push si-provider-fix-magisk.zip /data/local/tmp/
   adb shell su -c "ksud module install /data/local/tmp/si-provider-fix-magisk.zip"
   ```

   Magisk 用户可直接在管理器里刷入 zip。

2. **安装 LSPosed 模块**

   ```bash
   adb install -r si-provider-fix.apk
   ```

3. **在 LSPosed 管理器启用模块，勾选作用域**

   - `媒体存储` / `com.android.providers.media.module`
   - `Storage Isolation` / `moe.shizuku.redirectstorage`

4. **重启**

5. **测试**：在小黑盒（或其他配了导出规则的应用）里存一张图，检查文件落点与相册显示位置。

## 性能

| 指标 | 数值 |
|---|---|
| CPU 占用 | 0.003%（日均 2.9 秒） |
| 内存 | 5.2 MB |
| 日均唤醒 | 14,400 次 |
| 规则生效延迟 | < 100 ms |

采用 inotify 事件驱动，无空闲轮询。相比 3 秒轮询方案，唤醒次数降低 90%，CPU 降低 95%。

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

## 已知限制

- 只覆盖 MediaProvider，`DownloadProvider` 未处理（实测普通下载不进 MediaStore）
- 不支持多用户
- 依赖 root：`configuration.json` 仅 root 可读，MediaProvider 不在 KernelSU 允许列表内

## 校验

```
b1fd59d1f1119616015efe3ea7799a7c5efb27109bcefc479be3a101ebaef550  si-provider-fix-magisk.zip
bf4fe37fd9417ecb63ab7d0d3cecdc4ca59cb9d9034fd3a4d3cf14baaa3f9a07  si-provider-fix.apk
```

预编译产物使用本地调试密钥签名，长期使用建议自行重新签名。
