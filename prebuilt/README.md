# prebuilt

预编译产物，与仓库中源码对应。签名使用固定证书（见 `lsposed-module/SIGNING.md`）。

| 文件 | 说明 |
|---|---|
| `si-provider-fix-magisk.zip` | Magisk / KernelSU 模块，v2.0（inotify 事件驱动） |
| `si-provider-fix.apk` | LSPosed 模块，v2.1.2（versionCode 23，native mkdirat/mkdir 拦截 MiShare + com.miui.voiceassist） |

安装步骤见根目录 `README.md`。

## SHA-256

```
b1fd59d1f1119616015efe3ea7799a7c5efb27109bcefc479be3a101ebaef550  si-provider-fix-magisk.zip
d26af6b7d8d825033572ccee0f6ba5ce6c0387265040124cbb3e52a5ecb14b9c  si-provider-fix.apk
```

## 签名

```
CN=MentholTea, OU=Android, O=si-provider-fix, C=CN
证书 SHA-256: 0ef1b57bccf28f251aafe645958978fe669a287216fc68d59954c70c4d7355dd
```

```bash
apksigner verify --print-certs si-provider-fix.apk
```

由于签名固定，后续版本可以直接覆盖安装，无需先卸载。

## 自行构建

需要 Android SDK 和 JDK 17+：

```bash
export ANDROID_SDK_ROOT=/path/to/sdk
export JAVA_HOME=/path/to/jdk

cd lsposed-module
pwsh -File build.ps1
```

Magisk 模块是纯 shell，直接打包：

```bash
cd magisk-module
zip -r ../si-provider-fix-magisk.zip .
```

签名配置见 `lsposed-module/SIGNING.md`。
