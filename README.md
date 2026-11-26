<img src="assets/branding/app_icon.png" alt="NEUQ One 图标" width="144" />

# NEUQ One

面向东北大学秦皇岛分校学生的非官方轻量校园工具，使用 Flutter 构建，源码采用 [MIT 许可证](LICENSE)。

## 功能

应用登录后默认打开课表，底部可切换课表、成绩、服务和我的。

- **课表**：自动读取教务当前学期，按教学周和学校 12 个固定节次展示；支持已有课程编辑和 ICS 导出。
- **成绩**：读取历史成绩和教务 GPA；学期 GPA 缺少时，按对应入学年级的东秦规则计算。
- **空教室**：通过 NEUQ One Data 查看北京时间今天及未来六天的空教室，支持工学馆、科技楼和人文楼；区分全天空闲、下节有课和历史数据。
- 「服务」中的**校园地图**使用 NEUQ One Assets 提供的高清地图，支持手势缩放、横屏、全屏和缓存后的离线查看。
- 「服务」中的**学校政策**提供政策目录及原文 PDF 预览和保存。已缓存的目录和 PDF 可离线查看。
- **校园卡**：校园服务页展示并刷新按账号缓存的余额。打开官方卡务网页可使用校方充值页，并跳转微信或支付宝收银台。
- **校园邮箱**：用学校邮箱网页生成的客户端授权码，在 App 内查看文件夹、搜索和收发邮件，可保存附件。
- **就业活动**：读取就业信息网首页的宣讲会和招聘会，缓存 30 分钟，刷新失败时保留上次结果。
- **我的**提供统一身份认证状态、外观设置、课程提醒、隐私和项目说明。可通过「关于 NEUQ One」检查正式版本。

学期、课表、成绩和上次读取的校园卡余额保存在设备上，按学校账号隔离。离线或刷新失败时保留上次成功读取的数据。

## 当前状态

Android 调试 APK 已完成本地构建。登录和成绩显示已有真机反馈，公共空教室接入待真机复验。完整验收范围见[校园接入状态](docs/integration-status.md)。iOS 配置和代码已包含在仓库中，需要在 macOS / Xcode 环境完成构建和真机验证。

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

当前构建配置用于开发和测试，包括 release 构建所用的调试签名。需要正式分发时，请配置自己的发布签名；私钥和签名密码不应提交到仓库。

个人中心的 GitHub 入口默认指向本仓库。派生项目可以覆盖：

```sh
flutter build apk --debug --dart-define=NEUQ_ONE_REPOSITORY_URL=https://github.com/your-account/your-repo
```

空教室从 `https://neuq-one-data.pages.dev` 读取。地图、政策和 App 版本清单从 `https://neuq-one-assets.pages.dev` 读取。构建时可分别用 `NEUQ_ONE_DATA_ORIGIN` 和 `NEUQ_ONE_ASSETS_ORIGIN` 覆盖根地址。正式 Android 安装包通过 GitHub Releases 分发。[公共数据接口](docs/public-data.md) · [部署与正式发布](docs/deployment.md)

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

本项目与东北大学秦皇岛分校无隶属关系，正式校务信息以学校官方系统为准。教务登录将凭据提交给学校统一认证入口。Android 可主动选择「在此设备记住密码」，通过系统安全存储加密保存，在「我的」中可删除。退出时同时删除保存的学校密码、离线登录标识和本地会话。校园邮箱客户端授权码及校园卡余额和读取时间按账号加密存于本机。ICS 导出文件包含明文课表信息。

源码和构建配置不包含学校账号、真实学生数据或发布签名密钥。报告问题时请使用虚构数据，并移除截图中的个人信息。安全问题处理见 [SECURITY.md](SECURITY.md)。

原创源码采用 [MIT 许可证](LICENSE)，依赖项目遵循各自许可证。数据解析所参考的公开项目和学校资料列在[校园接入状态](docs/integration-status.md)中。
