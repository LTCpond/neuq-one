# 公共数据接口

这些 HTTPS 请求由 `PublicDataClient` 发出，无需学校认证。Flutter 的功能数据层通过 Riverpod 使用该客户端。

| 功能 | 默认根地址 | GET 路径 |
| --- | --- | --- |
| 空教室 | `https://neuq-one-data.pages.dev` | `/api/v1/classrooms/week.json` |
| 校园地图 | `https://neuq-one-assets.pages.dev` | `/assets/maps/campus-map.png` |
| 学校政策 | `https://neuq-one-assets.pages.dev` | `/assets/policies/index.json`、`/assets/policies/<id>.pdf` |
| App 检查更新 | `https://neuq-one-assets.pages.dev` | `/assets/app/latest.json` |

空教室服务也提供 `/api/v1/classrooms/today.json` 和 `/api/v1/status.json`。学校政策目录的 `sha256` 对应同一 `id` 的 PDF 字节。

版本清单继续使用 `schemaVersion: 1`。`release` 保留正式版语义，`prerelease` 提供公测版，两者可为 `null`。版本对象包含 `version`、`url`、`prerelease` 及可选的 `changelog` 字符串数组。旧清单只含 `release` 仍可使用，旧客户端会继续读取其中的正式版。版本按三个十进制整数比较，下载地址须与该版本的 GitHub Release 页面完全匹配。客户端最多接收 16 KiB，摘要以纯文本显示，最多五条、每条 160 个 Unicode 码点。[服务端接口契约](https://github.com/LTCpond/neuq-one-data/blob/main/docs/api.md)

构建时可通过两个独立的 `dart-define` 指定 HTTPS 根地址。

```sh
flutter run \
  --dart-define=NEUQ_ONE_DATA_ORIGIN=https://neuq-one-data.pages.dev \
  --dart-define=NEUQ_ONE_ASSETS_ORIGIN=https://neuq-one-assets.pages.dev
```

迁移期间旧数据域名继续提供与旧客户端兼容的地图和政策路径。新版会继续读取设备已有的有效地图及政策缓存。[部署顺序](deployment.md)
