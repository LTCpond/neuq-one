# Android 正式签名

## 本地签名

使用现有正式 Keystore。在本地创建 `android/key.properties`，以 UTF-8 保存并填入自己的配置。

```properties
storeFile=/private/path/to/release.jks
storePassword=<Keystore 密码>
keyAlias=<正式密钥别名>
keyPassword=<正式密钥密码>
```

`storeFile` 接受绝对路径和相对于 `android/` 的路径。Windows 路径可写成 `D:/private/release.jks`。按照 Java Properties 格式，值中的反斜杠写成 `\\`，前导空格写成 `\ `。Keystore 和 `android/key.properties` 应保存在本机并妥善备份，避免提交到仓库或复制到日志。

```sh
flutter pub get --enforce-lockfile
flutter build apk --release --split-per-abi --no-pub
```

输出目录为 `build/app/outputs/flutter-apk/`。Release 签名配置缺失或不完整时，Gradle 会终止构建。正式版包名为 `org.neuqone.neuq_one`。Debug 构建使用 Android 默认调试签名，包名为 `org.neuqone.neuq_one.debug`，可与正式版同时安装。此前以正式包名安装的旧调试包仍受 Android 的签名匹配规则约束。

覆盖已安装的 GitHub 正式版时，使用同一 ABI 的正式包。Flutter 的分 ABI 包使用带 ABI 偏移的版本码，通用 APK 的版本码按 `pubspec.yaml` 中的构建号生成。

手动分发前，对每个 APK 运行 `apksigner verify --print-certs <APK路径>`，并核对证书 SHA-256 指纹与正式 Keystore 中的证书一致。[Android apksigner 文档](https://developer.android.com/tools/apksigner)

对每个 APK 运行 `python3 .github/actions/verify-android/verify_notifications.py <aapt2路径> <APK路径>`，检查缩减后的通知图标是否存在，并核对合并 Manifest 中的通知、重启、精确闹钟权限及接收器。Debug CI 和正式签名发布流程使用同一个检查脚本。系统通知送达、精确闹钟权限变更和重启恢复需在对应设备上验收。

## GitHub Actions Secrets

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | 现有正式 Keystore 文件的 Base64 |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore 密码 |
| `ANDROID_KEY_ALIAS` | 正式密钥别名 |
| `ANDROID_KEY_PASSWORD` | 正式密钥密码 |

发布工作流仅在签名构建步骤读取这些 Secrets。它在 GitHub runner 上创建临时 Keystore 和 `android/key.properties`，对每个 ABI 的 APK 执行验签，并比较签名证书与 Keystore 指定别名的 SHA-256 指纹。步骤退出时删除临时签名文件。上传内容为已验签的 APK。[发布工作流](../.github/workflows/release.yml)
