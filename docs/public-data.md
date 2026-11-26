# 公共数据接口

Flutter 功能数据层通过 Riverpod 使用 `PublicDataClient`。公共资源请求采用 HTTPS，无需学校认证。

| 资源组 | Azure 主源 | Cloudflare 备用源 |
| --- | --- | --- |
| 空教室 | `https://blue-flower-0e0c87f00.4.azurestaticapps.net` | `https://neuq-one-data.pages.dev` |
| 地图、政策、App 版本清单 | `https://agreeable-wave-005580b00.4.azurestaticapps.net` | `https://neuq-one-assets.pages.dev` |

| 功能 | Azure GET 路径 | Cloudflare GET 路径 |
| --- | --- | --- |
| 七日空教室 | `/data/v1/classrooms/week.json` | `/api/v1/classrooms/week.json` |
| 当天空教室、采集状态 | `/data/v1/classrooms/today.json`、`/data/v1/status.json` | `/api/v1/classrooms/today.json`、`/api/v1/status.json` |
| 校园地图 | `/assets/maps/campus-map.png` | 同左 |
| 学校政策 | `/assets/policies/index.json`、`/assets/policies/<id>.pdf` | 同左 |
| App 检查更新 | `/assets/app/latest.json` | 同左 |

业务层使用表中的 Cloudflare 路径作为逻辑路径。网络层对 `*.azurestaticapps.net` 空教室站点转换前缀，避免与 Azure 的后端路由冲突。自定义空教室域名应提供 `/api/v1/`。[服务端路径与响应契约](https://github.com/LTCpond/neuq-one-data/blob/main/docs/api.md)

## 切换与缓存

每次操作优先尝试主源。连接或 DNS 失败、超时、HTTP 429 或 5xx、资源缺失、响应超限或内容校验失败时，尝试一次备用源。客户端拒绝 HTTP 重定向。连接、请求至收到响应头、读取空闲分别限制为 3 秒、4 秒、4 秒。JSON 操作共享 12 秒总时限，地图和 PDF 共享 30 秒。两源都可尝试时，主源最多使用总时限的三分之二。

连接、超时、限流或服务端错误触发对应源 45 秒冷却。空教室和静态资源各自维护主备健康状态。冷却结束后的首个请求可探测恢复；其他并发请求可直接走备用源。缺失或无效的单个文件仍会切换，站点的其他文件可以继续请求。诊断页记录源角色、耗时、失败分类、HTTP 状态、切换与恢复探测。

`ETag` 和 `Last-Modified` 与实际取得内容的完整资源 URL 一起保存。只有持有该资源的可用缓存时才发送对应的条件请求头。没有可靠来源的旧版缓存仍可读取，下次更新会完整下载。两源都无法提供有效内容时，空教室、地图和政策目录继续显示已验证的缓存，标明离线状态和更新时间。地图和政策目录使用内容保存时间。空教室使用采集时间，已过期时段按历史数据展示。

空教室七日快照最大 8 MiB。客户端校验结构、北京时间日期及每个时段的有效期。远程快照必须包含当天，并在当天或后续日期至少保留一项有效时段。过期缓存不能通过 HTTP 304 延长有效期。生成时间早于当前本地快照的响应不会覆盖缓存。

地图最大 25 MiB，校验 PNG 文件结构、尺寸和解码结果。政策目录最大 128 KiB，PDF 最大 25 MiB。PDF 必须符合所选政策条目的 SHA-256，客户端按文件标识和摘要缓存，因此两站发布进度不同期间也可以读取同一目录对应的 PDF。

版本清单使用 `schemaVersion: 1`，最大 16 KiB。`release` 提供正式版，`prerelease` 提供公测版，两者可为 `null`。旧清单可以只有 `release`。版本对象包含 `version`、`url`、`prerelease` 和可选的 `changelog` 字符串数组。版本按三个十进制整数比较，链接须完全匹配官方 GitHub Release 页面。摘要以纯文本显示，最多五条，每条最多 160 个 Unicode 码点。

## 构建参数

四个 `dart-define` 可独立覆盖 HTTPS 根地址，正式 Android 构建可使用同名 GitHub Actions 仓库变量。

```sh
flutter run \
  --dart-define=NEUQ_ONE_DATA_ORIGIN=https://blue-flower-0e0c87f00.4.azurestaticapps.net \
  --dart-define=NEUQ_ONE_DATA_BACKUP_ORIGIN=https://neuq-one-data.pages.dev \
  --dart-define=NEUQ_ONE_ASSETS_ORIGIN=https://agreeable-wave-005580b00.4.azurestaticapps.net \
  --dart-define=NEUQ_ONE_ASSETS_BACKUP_ORIGIN=https://neuq-one-assets.pages.dev
```

旧数据域名继续提供旧客户端使用的地图和政策路径。[部署顺序](deployment.md)
