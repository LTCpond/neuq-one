# 公共数据迁移与 App 发布

1. 在同一 Cloudflare 账户创建 `neuq-one-assets` Pages Direct Upload 项目，并在 `neuq-one-data` 仓库配置静态发布。保持现有空教室 Worker、定时触发和旧站兼容资源。[静态站部署说明](https://github.com/LTCpond/neuq-one-data/blob/main/docs/static-assets.md)
2. 先部署静态站，确认地图、政策目录、PDF 和版本清单可访问，并验证 ETag 条件 GET。用新版客户端验证空教室、静态资源和离线查看。自定义部署地址可通过编译参数指定。[公共数据接口和地址配置](public-data.md)
3. 配置仓库 Actions Secret `NEUQ_ASSETS_DISPATCH_TOKEN`，使用仅限 `LTCpond/neuq-one-data` 且拥有 Actions 读写权限的细粒度 PAT。准备与 App 包版本匹配的 `vMAJOR.MINOR.PATCH` Release 草稿。先上传使用正式发布密钥签名的 Android APK，再将 Release 发布为 Latest。当前仓库默认 release 构建配置用于本地开发，需要另行配置正式签名。[GitHub Releases](https://github.com/LTCpond/neuq-one/releases)
4. 正式发布会运行 **Update app version manifest**，随后在 Data 仓库运行 **Deploy static assets**。确认静态站清单指向刚发布的版本，再用较旧的新版客户端打开「我的 → 关于 NEUQ One → 检查更新」验证入口。APK 由 GitHub Releases 提供。

自动化发布使用 GitHub App 令牌或 PAT 时，可以由 `release.published` 触发版本工作流。若使用内置 `GITHUB_TOKEN` 发布，需在发布成功后显式触发 Data 仓库的 `assets.yml`。[GitHub 自动令牌认证](https://docs.github.com/en/actions/security-for-github-actions/security-guides/automatic-token-authentication)
