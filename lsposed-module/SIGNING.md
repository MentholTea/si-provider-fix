# 签名配置说明

`build.ps1` 需要一个**固定的** keystore，否则每次构建出来的 APK 签名不同，
用 `adb install -r` 覆盖安装会报 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`。

## 仓库不包含密钥

`.gitignore` 排除了 `release.keystore`、`*.keystore`、`*.jks`、`keystore.properties`。
密钥只存在于本地。

## 首次配置

```bash
keytool -genkeypair \
    -keystore release.keystore \
    -storepass <你的密码> \
    -keypass <你的密码> \
    -alias siproviderfix \
    -keyalg RSA -keysize 2048 -validity 36500 \
    -dname "CN=YourName, OU=Android, O=si-provider-fix, C=CN"
```

然后在 `lsposed-module/keystore.properties` 里填入：

```properties
storeFile=../release.keystore
storePassword=<你的密码>
keyPassword=<你的密码>
keyAlias=siproviderfix
```

`storeFile` 相对于 `keystore.properties` 所在目录解析。

## 解析顺序

`build.ps1` 按以下顺序找签名材料：

1. 命令行参数：`-Keystore -StorePass -KeyPass -KeyAlias`
2. `lsposed-module/keystore.properties`
3. `<repo>/release.keystore`（配合环境变量或参数提供密码）
4. 都没有时生成一个**临时**密钥并打印警告

第 4 种情况产出的 APK 只适合本地尝鲜，不要用于分发。

## CI / 自动化

```bash
export ANDROID_SDK_ROOT=/path/to/sdk
export JAVA_HOME=/path/to/jdk

pwsh -File lsposed-module/build.ps1 \
    -Keystore /secure/release.keystore \
    -StorePass "$KS_PASS" \
    -KeyPass "$KS_PASS" \
    -KeyAlias siproviderfix
```

密码通过参数传入，不会写进任何文件。

## 校验指纹

```bash
apksigner verify --print-certs si-provider-fix.apk
```

应当输出你 keystore 的 SHA-256 指纹。官方 Release 使用的证书：

```
CN=MentholTea, OU=Android, O=si-provider-fix, C=CN
SHA-256: 0ef1b57bccf28f251aafe645958978fe669a287216fc68d59954c70c4d7355dd
```
