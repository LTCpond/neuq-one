# 参与贡献

欢迎提交问题反馈或 Pull Request。开发环境和启动步骤见 [README](README.md)。

## 代码约定

- 功能按 feature-first 组织，页面通过 Riverpod 使用数据层接口。
- 数据库查询、文件操作和网络调用放在数据层；远程同步失败时保留旧数据。
- 面向用户的提示使用简体中文。虚构示例必须明确标注为演示数据。
- 学校登录使用应用内官方网页，其他校园链接使用系统浏览器。新增远程数据源需要说明来源、授权前提、缓存有效性和失败策略。
- 不在源码、测试、日志、Issue 或截图中放入学校凭据、真实学生数据、Cookie 或签名密钥。测试使用虚构数据。
- PowerShell 环境优先使用 PowerShell 7。

## 提交前检查

```sh
dart format lib test
flutter analyze
flutter test
```

修改 Drift 或 JSON 模型后，先执行 `dart run build_runner build`，一并提交生成文件。修改 Android 配置或原生桥接后，补跑 `flutter build apk --debug`。

提交说明应描述用户遇到的问题、修改后的行为和已运行的验证。涉及界面的修改可附使用虚构数据的截图；涉及校园系统的修改应说明真机验证情况。

涉及 Android 通知时，使用 `verify_notifications.py` 检查 APK 内实际打包的图标和合并 Manifest，并分别记录 Android 13+ 通知授权、精确闹钟授权、非精确模式、重启和覆盖安装的设备验收结果。[Android 签名与 APK 检查](docs/android-signing.md)

校园访问回归使用 `flutter test test/campus_access_test.dart test/neuq_webvpn_protocol_test.dart test/neuq_client_test.dart`。模拟服务覆盖选路、CAS 表单、会话隔离和浏览器交互。原生启用需要单独记录获授权的学校环境验收结果。[Android 真机验收](docs/campus-access.md#android-真机验收)

## 资源与依赖

原始图标位于 `assets/branding/app_icon.png`。Android 自适应图标使用额外内边距抵消系统裁切，修改图标时保留原图留白；iOS 图标须使用无 alpha 通道的 PNG。

修改依赖时同时提交 `pubspec.yaml` 与 `pubspec.lock`。工具链、构建产物、设备数据和私钥由 `.gitignore` 排除，不应加入版本控制。
