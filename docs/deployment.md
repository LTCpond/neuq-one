# 公共数据迁移与 App 发布

## 静态站部署

1. 在同一 Cloudflare 账户创建 `neuq-one-assets` Pages Direct Upload 项目，并在 `neuq-one-data` 仓库配置静态发布。保持现有空教室 Worker、定时触发和旧站兼容资源。[静态站部署说明](https://github.com/LTCpond/neuq-one-data/blob/main/docs/static-assets.md)
2. 先部署静态站，确认地图、政策目录、PDF 和版本清单可访问，并验证 ETag 条件 GET。用新版客户端验证空教室、静态资源和离线查看。自定义部署地址可通过编译参数指定。[公共数据接口和地址配置](public-data.md)
3. 在 App 仓库配置 Actions Secret `NEUQ_ASSETS_DISPATCH_TOKEN`，使用仅限 `LTCpond/neuq-one-data` 且拥有 Actions 读写权限的细粒度 PAT。

## 标签自动发布

1. 更新 `pubspec.yaml` 的版本和 Android 构建号，构建号必须大于已使用的构建号。提交并合并变更后，使用版本中 `+` 之前的部分作为标签。例如 `0.1.0+17` 对应标签 `v0.1.0`。
2. 确认仓库已配置正式签名 Secrets。准备发布时，在目标提交上创建标签并推送到 `origin`。[Android 签名配置](android-signing.md)
3. 标签指向的提交使用 `.github/release-channel` 设置 `beta` 或 `stable`。公测阶段提交 `beta`，工作流会发布为预发行版。只有明确准备正式发布时才在目标提交改为 `stable`，发布为 Latest。相同的渠道配置写入 APK 的 `NEUQ_ONE_UPDATE_CHANNEL`，随安装包保留。手工构建正式包时也要传入 `--dart-define=NEUQ_ONE_UPDATE_CHANNEL=stable`。
4. **Android Release** 复用常规 CI 的工具链和检查，构建 `armeabi-v7a`、`arm64-v8a`、`x86_64` 三个 APK。验签通过后，GitHub CLI 上传 APK，并将维护者摘要放在自动生成的 Release Notes 前面。[发布工作流](../.github/workflows/release.yml) · [GitHub Releases](https://github.com/LTCpond/neuq-one/releases)
5. 任一渠道发布成功后，工作流使用 `NEUQ_ASSETS_DISPATCH_TOKEN` 触发 Data 仓库 `main` 上的 `assets.yml`。由内置 `GITHUB_TOKEN` 创建的 Release 需要此显式触发。[GitHub 工作流触发规则](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow#triggering-a-workflow-from-a-workflow)

## 填写更新摘要

在目标提交新增 `.github/release-notes/vMAJOR.MINOR.PATCH.md`，或者在手工发布时填写 Release Notes。使用独立的 `## 本次更新` 二级标题和 3～5 条面向用户的中文列表。每条最多显示 160 个 Unicode 码点。标题之外的 Release Notes 及自动生成的 PR 链接留在 GitHub 阅读。未提供摘要的版本仍可正常检查。

```markdown
## 本次更新

- 修复课程提醒的显示问题
- 改善空教室数据刷新提示
- 优化个人中心的教务状态显示
```

## 手动发布和验证

`v0.1.0+18` 延用 `v0.1.0` 公测版本号，只递增构建号。重发前核对旧远端标签已撤回，再按公测渠道流程发布。同版本号的旧公测包可从 Release 页面手动下载较高构建号并覆盖安装，签名与包名须一致。

手动发布时，使用与版本匹配的标签创建 Release 草稿，上传已验签的 APK，并确认 GitHub 的发布类型与 APK 的构建渠道一致。**Update app version manifest** 监听发布、编辑、撤回和删除事件。若事件由内置令牌操作产生或触发失败，可在 App 仓库的 Actions 手动运行此工作流，也可重跑 Data 的 **Deploy static assets**。[版本清单工作流](../.github/workflows/app-version.yml)

先部署 Data 端的双渠道清单，再使用更新后的 App 发布流程。发布后在 Data 仓库确认 **Deploy static assets** 成功，核对 `release` 与 `prerelease` 的版本、下载地址及摘要，再从较旧客户端的「我的」手动检查。正式客户端只读取正式版，公测客户端比较两个渠道并选版本最高的一项，同版本时优先正式版。[线上版本清单](https://neuq-one-assets.pages.dev/assets/app/latest.json)
