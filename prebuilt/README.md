# prebuilt

预编译产物，与仓库中源码对应。

| 文件 | 说明 |
|---|---|
| `si-provider-fix-magisk.zip` | Magisk / KernelSU 模块，v2.0（inotify 事件驱动） |
| `si-provider-fix.apk` | LSPosed 模块，v2.0（versionCode 20） |

安装步骤见根目录 `README.md`。

## SHA-256

```
b1fd59d1f1119616015efe3ea7799a7c5efb27109bcefc479be3a101ebaef550  si-provider-fix-magisk.zip
bf4fe37fd9417ecb63ab7d0d3cecdc4ca59cb9d9034fd3a4d3cf14baaa3f9a07  si-provider-fix.apk
```

## 自行构建

- LSPosed 模块：`cd lsposed-module && pwsh -File build.ps1`
- Magisk 模块：`cd magisk-module && zip -r ../si-provider-fix-magisk.zip .`

预编译产物使用本地调试密钥签名。如需长期分发，建议用自己的密钥重新签名：

```bash
keytool -genkeypair -keystore my.keystore -alias mykey \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass <password> -keypass <password> -dname "CN=YourName"

apksigner sign --ks my.keystore --out si-provider-fix.apk si-provider-fix-unsigned.apk
```
