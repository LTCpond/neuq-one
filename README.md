<img src="assets/branding/app_icon.png" alt="NEUQ One 图标" width="144" />

# NEUQ One

NEUQ One 是面向东北大学秦皇岛分校学生的非官方校园工具。用学校统一身份认证账号登录后，可以查看课表、成绩和培养方案，管理考试安排，并访问常用校园服务。

## 下载与使用

[下载 Android v0.1.2 公测版](https://github.com/LTCpond/neuq-one/releases/tag/v0.1.2)（构建号 20）。大多数 Android 手机请选择 `arm64-v8a` APK。发布页也提供 `armeabi-v7a` 和 `x86_64` 安装包。

登录后默认进入课表。底部导航可切换「课表」「学业」「服务」「我的」。如果校方要求额外验证，可以从 App 打开官方教务入口。Android 用户可选择在本机加密记住密码，供「重新连接教务」使用。

当前提供 Android 公测安装包。iOS 源码需要在 macOS 和 Xcode 环境中完成构建及真机验证。各校园服务的接入和验证进度见[校园接入状态](docs/integration-status.md)。

## 功能

| 入口 | 可以做什么 |
| --- | --- |
| 课表 | 按学校 12 个固定节次查看周课表，左右滑动时以动画切换教学周。可编辑本地课表、导出 ICS，并设置上课前 5、10、15 或 30 分钟提醒。 |
| 学业 → 成绩 | 查看单学期或全部学期成绩、累计 GPA 和学期 GPA 趋势。优先显示教务提供的 GPA，缺少学期 GPA 时按对应入学年级的规则计算。 |
| 学业 → 培养方案 | 查看课程类别、学分完成进度和课程状态，并确认替代课程的成绩。 |
| 学业 → 考试安排 | 在本机手动添加、编辑和删除考试。 |
| 服务 | 查空教室、浏览校园地图及学校政策 PDF、查询校园卡余额、查看就业活动，或打开学校官方站点。 |
| 服务 → 校园邮箱 | 用学生邮箱的客户端专用密码查看文件夹、搜索、收发邮件和保存附件。可先在[东北大学学生邮箱](https://mails.neu.edu.cn/)网页端生成专用密码。 |
| 我的 | 管理本地登录凭据、课程提醒和缓存，查看诊断记录，并手动检查更新。缓存管理按资源显示占用空间，支持逐项或一键清理。 |

已同步的学期、课表、成绩和培养方案，以及手动录入的考试安排，都可离线查看。个人学业数据和最近一次读取的校园卡余额按学校账号保存。空教室、校园地图和学校政策可使用已下载的缓存。刷新失败时会保留上次成功读取的数据。[公共数据与缓存说明](docs/public-data.md)

「服务 → WebVPN」在系统浏览器打开学校官方入口。本版本已加入校园网络选路与 WebVPN 会话管理能力，为后续接入获授权的校园资源做准备。App 内 WebVPN 认证在当前公测版处于关闭状态。[校园网络访问说明](docs/campus-access.md)

## v0.1.2 更新

- 课表加入左右滑动切周动画。
- 学业中心新增培养方案和本地考试安排。成绩可查看全部学期，并通过趋势图查看 GPA 变化。
- 重新设计登录页，修复 Android 已保存密码后重新连接教务仍要求输入密码的问题。
- 优化缓存管理界面，校园邮箱沿用上一版优化后的界面。
- 增加 WebVPN 底层支持，为后续校园业务接入做准备。

## 本地开发

使用 Flutter **3.50.1** 和 Dart **3.14.0**。Android 构建使用 JDK **17**、Android SDK **35 / 36 / 37.0**、Build Tools **36.0.0**、NDK **28.2.13676358** 和 CMake **3.22.1**。本地 SDK 路径通过 `android/local.properties` 配置。

```sh
git clone https://github.com/LTCpond/neuq-one.git
cd neuq-one
flutter pub get --enforce-lockfile
flutter run
```

提交前运行以下检查。修改 Drift 或 JSON 模型后，先运行 `dart run build_runner build` 并提交生成文件。改动 Android 配置后补跑调试构建。

```sh
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
```

Android 调试包输出到 `build/app/outputs/flutter-apk/app-debug.apk`，应用名为 **NEUQ One Dev**，可与公测版同时安装。也可从仓库的 [GitHub Actions](https://github.com/LTCpond/neuq-one/actions) 下载 `neuq-one-debug`。

推送与 `pubspec.yaml` 版本匹配的标签后，GitHub Actions 会验证源码、构建并验签三个架构的 APK、发布 Release 并触发 App 更新清单刷新。标签所在提交的 `.github/release-channel` 决定发布渠道，当前为 `beta`。[部署与发布](docs/deployment.md) · [Android 签名](docs/android-signing.md)

[贡献指南](CONTRIBUTING.md) · [项目架构](docs/architecture.md) · [路线图](docs/roadmap.md)

## 隐私与许可

学校账号凭据只提交给校方统一认证入口。Android 用户可在「我的」删除本机保存的密码，退出时会清除已保存的学校密码和本地登录状态。校园邮箱客户端专用密码保存在系统安全存储中。ICS 文件包含明文课表，分享前请留意其中的个人信息。

NEUQ One 与学校无隶属关系，正式校务信息以学校系统为准。反馈问题时请使用虚构数据，并从截图和日志中移除个人信息。[安全问题报告](SECURITY.md)

原创源码采用 [MIT 许可证](LICENSE)，依赖项目遵循各自许可证。
