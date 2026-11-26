# 公共数据迁移与 App 发布

## 静态站部署

1. 在同一 Cloudflare 账户创建 `neuq-one-assets` Pages Direct Upload 项目，并在 `neuq-one-data` 仓库配置静态发布。保持现有空教室 Worker、定时触发和旧站兼容资源。[静态站部署说明](https://github.com/LTCpond/neuq-one-data/blob/main/docs/static-assets.md)
2. 先部署静态站，确认地图、政策目录、PDF 和版本清单可访问，并验证 ETag 条件 GET。用新版客户端验证空教室、静态资源和离线查看。自定义部署地址可通过编译参数指定。[公共数据接口和地址配置](public-data.md)
3. 在 App 仓库配置 Actions Secret `NEUQ_ASSETS_DISPATCH_TOKEN`，使用仅限 `LTCpond/neuq-one-data` 且拥有 Actions 读写权限的细粒度 PAT。

## 标签自动发布

1. 更新 `pubspec.yaml` 的版本和 Android 构建号，构建号必须大于已使用的构建号。提交并合并变更后，使用版本中 `+` 之前的部分作为标签。例如 `0.1.0+17` 对应标签 `v0.1.0`。
2. 确认仓库已配置正式签名 Secrets。准备发布时，在目标提交上创建标签并推送到 `origin`。[Android 签名配置](android-signing.md)
3. **Android Release** 复用常规 CI 的工具链和检查，构建 `armeabi-v7a`、`arm64-v8a`、`x86_64` 三个 APK。验签通过后，GitHub CLI 生成更新日志并上传 APK。`v0.1.0` 发布为公开预发行版，其他版本发布为 Latest。[发布工作流](../.github/workflows/release.yml) · [GitHub Releases](https://github.com/LTCpond/neuq-one/releases)
4. 正式 Release 发布成功后，工作流使用 `NEUQ_ASSETS_DISPATCH_TOKEN` 显式触发 Data 仓库 `main` 上的 `assets.yml`。内置 `GITHUB_TOKEN` 创建的 Release 不会触发 App 仓库的 `release.published` 工作流。[GitHub 工作流触发规则](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow#triggering-a-workflow-from-a-workflow)

## 手动发布和验证

手动发布时，使用与版本匹配的标签创建 Release 草稿，上传已验签的正式 APK，然后发布为 Latest。原有的 **Update app version manifest** 会监听 `release.published` 并自动触发静态部署，同一次发布只需使用这个入口。[版本清单工作流](../.github/workflows/app-version.yml)

发布后，在 Data 仓库确认 **Deploy static assets** 已成功，检查版本清单的 `release.version` 和 `release.url`，再用较旧版本的客户端打开「我的」，在「关于」分组点击「检查更新」。若自动发布成功后仅清单触发失败，重跑失败的 Actions 作业即可重试该步骤。[线上版本清单](https://neuq-one-assets.pages.dev/assets/app/latest.json)
