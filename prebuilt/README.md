# prebuilt

预编译产物，与仓库中源码对应。

| 文件 | 说明 |
|---|---|
| `si-provider-fix-magisk.zip` | Magisk / KernelSU 模块，v2.0（inotify 事件驱动） |
| `si-provider-fix.apk` | LSPosed 模块 |

安装见根目录 `README.md`。

## 校验

```bash
sha256sum *.zip *.apk
```

## 自行构建

参考 `../lsposed-module/build.ps1` 和 `../magisk-module/`（纯 shell，直接 zip 打包）。

预编译产物的签名用的是本地调试密钥，如果你要长期使用，建议自己重新签名。
