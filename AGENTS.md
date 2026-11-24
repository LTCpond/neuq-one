# NEUQ One 工程约定

- PowerShell 环境优先使用 PowerShell 7（pwsh）。
- 功能按 feature-first 组织。页面依赖 Riverpod 提供的接口。Drift 查询、文件访问和网络调用放在数据层。
- 学期、课表、成绩与考试都应能离线使用。新增远程适配器前先明确授权、来源、缓存有效性和失败策略。失败时保留旧数据。
- 面向用户的提示使用简体中文。演示数据在入口和数据展示处标明来源。
- 使用学校已核实的 HTTPS 入口。学校登录由应用内官方网页处理，其他校园链接使用系统浏览器。学校凭据、真实学生信息和签名密钥不得进入仓库或日志。
- 修改 Drift 或 JSON 模型后，运行 `dart run build_runner build`，提交生成文件。
- 提交前运行 `dart format lib test`、`flutter analyze`、`flutter test`。改动 Android 配置时补跑 `flutter build apk --debug`。
