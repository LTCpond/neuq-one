<img src="assets/branding/app_icon.png" alt="NEUQ One 图标" width="144" />

# NEUQ One

面向东北大学秦皇岛分校学生的非官方校园工作台，使用 Flutter 构建，源码采用 [MIT 许可证](LICENSE)。

## 功能

- **首页**：北京时间、教学周、今日课程和最近考试；可选择并拖动排序常用校园服务。
- **课表**：自动读取教务当前学期，按教学周和学校 12 个固定节次展示；支持已有课程编辑和 ICS 导出。
- **成绩**：读取历史成绩和教务 GPA；学期 GPA 缺少时，按对应入学年级的东秦规则计算。
- **空教室**：查询当天六个时段，支持工学馆、科技楼和人文楼；区分全天空闲和下节有课。
- **校园卡**：打开官方卡务网页，按账号缓存余额；支持校方充值页跳转微信或支付宝收银台。
- **我的**：统一身份认证状态、外观设置、课程提醒、隐私和项目说明。

学期、课表、成绩、考试和上次读取的校园卡余额保存在设备上，按学校账号隔离。离线或刷新失败时保留上次成功读取的数据。

## 当前状态

Android 调试 APK 已完成本地构建。登录、成绩显示及空教室查询已有真机反馈；完整验收范围见[校园接入状态](docs/integration-status.md)。iOS 配置和代码已包含在仓库中，需要在 macOS / Xcode 环境完成构建和真机验证。

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
  app/         登录门禁、路由和应用配置
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

本项目与东北大学秦皇岛分校无隶属关系，正式校务信息以学校官方系统为准。学校官方网页处理密码和验证码，应用不保存学校密码。应用使用账号派生标识隔离本地数据，退出时清理本地登录标识及内嵌浏览器 Cookie；校园卡余额和读取时间按账号加密存于本机。ICS 导出文件包含明文课表信息。

源码和构建配置不包含学校账号、真实学生数据或发布签名密钥。报告问题时请使用虚构数据，并移除截图中的个人信息。安全问题处理见 [SECURITY.md](SECURITY.md)。

原创源码采用 [MIT 许可证](LICENSE)，依赖项目遵循各自许可证。数据解析所参考的公开项目和学校资料列在[校园接入状态](docs/integration-status.md)中。
