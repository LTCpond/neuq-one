<img src="assets/branding/app_icon.png" alt="NEUQ One 图标" width="144" />

# NEUQ One

面向东北大学秦皇岛分校学生的非官方轻量校园工具，使用 Flutter 构建，源码采用 [MIT 许可证](LICENSE)。

[下载 Android v0.1.0 公测版](https://github.com/LTCpond/neuq-one/releases/tag/v0.1.0)。常见 Android 手机请选择 `arm64-v8a` APK。

## 功能

应用登录后默认打开课表，底部可切换课表、成绩、服务和我的。

- **课表**：自动读取教务当前学期，按教学周和学校 12 个固定节次展示；支持已有课程编辑和 ICS 导出。
- **成绩**：读取历史成绩和教务 GPA；学期 GPA 缺少时，按对应入学年级的东秦规则计算。
- **空教室**展示北京时间七日快照和各楼栋采集时间。页面可见时约每五分钟检查一次，过期时尝试更新，离线时保留最近快照。
- 「服务」中的**校园地图**使用 NEUQ One Assets 提供的高清地图，支持手势缩放、横屏、全屏和缓存后的离线查看。
- 「服务」中的**学校政策**提供政策目录及原文 PDF 预览和保存。已缓存的目录和 PDF 可离线查看。
- **校园卡**：校园服务页展示并刷新按账号缓存的余额。打开官方卡务网页可使用校方充值页，并跳转微信或支付宝收银台。
- **校园邮箱**：支持东北大学学生邮箱。使用网页生成的客户端专用密码，可在 App 内查看文件夹、搜索和收发邮件，并保存附件。[东北大学学生邮箱](https://mails.neu.edu.cn/)
- **就业活动**：读取就业信息网首页的宣讲会和招聘会，缓存 30 分钟，刷新失败时保留上次结果。
- **我的**提供本地身份、教务会话状态、课程提醒、缓存管理和诊断信息。可按北京时间在上课前 5、10、15 或 30 分钟接收本地通知，也可独立发送测试通知。
- **更新**在启动后异步检查，成功检查间隔为 24 小时。同一版本最多主动提示一次，「我的 → 检查更新」会保留可用版本提示并可随时手动检查。更新摘要来自发布清单，下载通过 GitHub Releases 完成。

学期、课表、成绩和上次读取的校园卡余额保存在设备上，按学校账号隔离。离线或刷新失败时保留上次成功读取的数据。

## 当前状态

登录和成绩显示已有 Android 真机反馈，公共空教室接入待真机复验。完整验收范围见[校园接入状态](docs/integration-status.md)。iOS 配置和代码已包含在仓库中，需要在 macOS / Xcode 环境完成构建和真机验证。

校园卡网页的“扫一扫”在普通浏览器中也无响应，目前仅确认微信小程序内可用，可能依赖微信环境。应用已补齐相机授权支持，尚未完成该入口的扫码适配。

## 构建与运行

工具版本：

- Flutter **3.50.1** / Dart **3.14.0**。
- Android：JDK **17**，Android SDK **35 / 36 / 37.0**、Build Tools **36.0.0**、NDK **28.2.13676358**、CMake **3.22.1**。
- iOS：macOS 和 Xcode。

```sh
git clone https://github.com/LTCpond/neuq-one.git
cd neuq-one
flutter pub get --enforce-lockfile
flutter run
```

Android 工具路径由本机的 `android/local.properties` 配置，不提交到仓库。构建调试 APK：

```sh
flutter build apk --debug
```

输出：`build/app/outputs/flutter-apk/app-debug.apk`。GitHub Actions 也会在检查通过后生成 `neuq-one-debug` 构建产物，可从仓库的 [Actions](https://github.com/LTCpond/neuq-one/actions) 下载。

本地 Release 构建需要正式签名配置。推送与 `pubspec.yaml` 版本匹配的 `vMAJOR.MINOR.PATCH` 标签后，GitHub Actions 会构建并验证三个 ABI 的 APK。标签指向的提交通过 `.github/release-channel` 指定发布渠道，当前为 `beta`。`stable` 构建只接收正式版本，`beta` 构建可以接收更高的公测或正式版本。两个渠道都会触发版本清单刷新。[Android 签名配置](docs/android-signing.md) · [部署与 App 发布](docs/deployment.md)

个人中心的 GitHub 入口默认指向本仓库。派生项目可以覆盖：

```sh
flutter build apk --debug --dart-define=NEUQ_ONE_REPOSITORY_URL=https://github.com/your-account/your-repo
```

空教室、校园地图、学校政策和 App 版本清单优先从 Azure Static Web Apps 读取，发生故障时切换到 Cloudflare Pages。空教室和静态资源各自配置主备地址。双源都无法提供可用数据时，空教室、地图和政策目录继续显示已验证的本地缓存，并标明离线状态及更新时间。构建时可通过四个 `dart-define` 覆盖地址，正式构建也支持同名 GitHub Actions 仓库变量。[公共数据接口与构建参数](docs/public-data.md)

请按设备架构下载 Android 安装包，常见的 64 位 ARM 手机使用 `arm64-v8a`。[GitHub Releases](https://github.com/LTCpond/neuq-one/releases)

## 开发与验证

```sh
dart run build_runner build
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
```

修改 Drift 或 JSON 模型后，需要重新生成并提交 `*.g.dart`。完整贡献流程见 [CONTRIBUTING.md](CONTRIBUTING.md)。

```text
lib/
  app/         登录门禁、四栏导航、前台恢复和应用配置
  core/        数据库、认证、网络、时间和共享组件
  features/    按业务功能组织的数据层、领域模型和页面
test/          业务、存储、协议与界面测试
assets/        原始品牌图标
android/       Android 工程与原生桥接
ios/           iOS 工程
docs/          架构、接入状态与路线图
```

[架构](docs/architecture.md) · [路线图](docs/roadmap.md) · [持续集成](.github/workflows/ci.yml)

## 隐私与许可

本项目与东北大学秦皇岛分校无隶属关系，正式校务信息以学校官方系统为准。教务登录将凭据提交给学校统一认证入口。Android 可主动选择「在此设备记住密码」，通过系统安全存储加密保存，在「我的」中可删除。退出时同时删除保存的学校密码、离线登录标识和本地会话。校园邮箱客户端专用密码及校园卡余额和读取时间按账号加密存于本机。ICS 导出文件包含明文课表信息。

源码和构建配置不包含学校账号、真实学生数据或发布签名密钥。报告问题时请使用虚构数据，并移除截图中的个人信息。安全问题处理见 [SECURITY.md](SECURITY.md)。

「我的 → 缓存管理」只清理公共资源和文件选择器临时副本。诊断记录最多保留 150 条，保存在本次运行的内存中，包含发生时间、模块、阶段、错误分类和异常类型。诊断记录可在设备上查看、清除或手动复制。

原创源码采用 [MIT 许可证](LICENSE)，依赖项目遵循各自许可证。数据解析所参考的公开项目和学校资料列在[校园接入状态](docs/integration-status.md)中。
