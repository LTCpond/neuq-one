# 公共数据迁移与 App 发布

## 静态站部署

1. 在同一 Cloudflare 账户创建 `neuq-one-assets` Pages Direct Upload 项目，并在 `neuq-one-data` 仓库配置静态发布。保持现有空教室 Worker、定时触发和旧站兼容资源。[静态站部署说明](https://github.com/LTCpond/neuq-one-data/blob/main/docs/static-assets.md)
2. 先部署静态站，确认地图、政策目录、PDF 和版本清单可访问，并验证 ETag 条件 GET。用新版客户端验证空教室、静态资源和离线查看。自定义部署地址可通过编译参数指定。[公共数据接口和地址配置](public-data.md)
3. 在 App 仓库配置 Actions Secret `NEUQ_ASSETS_DISPATCH_TOKEN`，使用仅限 `LTCpond/neuq-one-data` 且拥有 Actions 读写权限的细粒度 PAT。

## 标签自动发布

1. 先合并 Data 仓库的清单生成变更，确认 Azure 和 Cloudflare Pages 的静态资源部署成功。更新 App 仓库的 `pubspec.yaml`，使用未发布过的版本号和更高的 Android 构建号。标签使用 `+` 之前的版本号，例如 `0.2.0+21` 对应 `v0.2.0`。
2. 确认 App 仓库已有正式签名 Secrets、`R2_ACCESS_KEY_ID`、`R2_SECRET_ACCESS_KEY`、`R2_ENDPOINT`、`R2_BUCKET` 和 `R2_PUBLIC_URL`。后者为 `https://download.neuq.one`。准备发布时，手动在目标提交上创建标签并推送到 `origin`。[Android 签名配置](android-signing.md)
3. 标签指向的提交使用 `.github/release-channel` 设置 `beta` 或 `stable`。公测阶段提交 `beta`，工作流会发布为预发行版。只有明确准备正式发布时才在目标提交改为 `stable`，发布为 Latest。相同的渠道配置写入 APK 的 `NEUQ_ONE_UPDATE_CHANNEL`，随安装包保留。手工构建正式包时也要传入 `--dart-define=NEUQ_ONE_UPDATE_CHANNEL=stable`。
4. **Android Release** 复用常规 CI 的工具链和检查，构建 `armeabi-v7a`、`arm64-v8a`、`x86_64` 三个 APK。验签后使用 R2 条件写入上传至 `releases/v<版本>/`，核对 S3 对象和公开下载响应的大小及 SHA-256。全部通过后，将三个 APK 和 `apk-downloads.json` 上传到 GitHub Release 草稿，核验附件后发布。维护者摘要放在自动生成的 Release Notes 前面。[发布工作流](../.github/workflows/release.yml) · [GitHub Releases](https://github.com/LTCpond/neuq-one/releases)
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

R2 上传或 GitHub 发布失败时，在原 **Android Release** 运行中选择 **Re-run failed jobs**，复用保留七天的已验签 APK 构建产物。相同内容会通过校验并跳过重复写入。若同版本内容冲突，保留现有文件，为新 APK 使用新版本号。若只有清单触发失败，可重跑该失败任务或手动运行 **Update app version manifest**。

手动发布时，使用与版本匹配的标签创建 Release 草稿，上传已验签的 APK，并确认 GitHub 的发布类型与 APK 的构建渠道一致。**Update app version manifest** 监听发布、编辑、撤回和删除事件。若事件由内置令牌操作产生或触发失败，可在 App 仓库的 Actions 手动运行此工作流，也可重跑 Data 的 **Deploy static assets**。[版本清单工作流](../.github/workflows/app-version.yml)

发布后在 Data 仓库确认 **Deploy static assets** 的 Azure 和 Cloudflare Pages 任务成功。核对两站清单的渠道、三种 APK 的 `downloads`、GitHub Release 页面地址及摘要。分别从较旧客户端和支持 R2 的客户端进入「我的」手动检查，验证 Release 页面、匹配 ABI 的 R2 下载及 GitHub 备用下载。正式客户端只读取正式版，公测客户端比较两个渠道并选版本最高的一项，同版本时优先正式版。[线上版本清单](https://neuq-one-assets.pages.dev/assets/app/latest.json)
