# 公共数据接口

这些 HTTPS 请求由 `PublicDataClient` 发出，无需学校认证。Flutter 的功能数据层通过 Riverpod 使用该客户端。

| 功能 | 默认根地址 | GET 路径 |
| --- | --- | --- |
| 空教室 | `https://neuq-one-data.pages.dev` | `/api/v1/classrooms/week.json` |
| 校园地图 | `https://neuq-one-assets.pages.dev` | `/assets/maps/campus-map.png` |
| 学校政策 | `https://neuq-one-assets.pages.dev` | `/assets/policies/index.json`、`/assets/policies/<id>.pdf` |
| App 检查更新 | `https://neuq-one-assets.pages.dev` | `/assets/app/latest.json` |

空教室服务也提供 `/api/v1/classrooms/today.json` 和 `/api/v1/status.json`。学校政策目录的 `sha256` 对应同一 `id` 的 PDF 字节。版本清单 `schemaVersion` 为 `1`，`release` 为 `null` 或包含 `version` 和 `url` 的正式发布对象。版本号按三个十进制整数比较，下载入口为该版本的 GitHub Release 页面。[服务端接口契约](https://github.com/LTCpond/neuq-one-data/blob/main/docs/api.md)

构建时可通过两个独立的 `dart-define` 指定 HTTPS 根地址。

```sh
flutter run \
  --dart-define=NEUQ_ONE_DATA_ORIGIN=https://neuq-one-data.pages.dev \
  --dart-define=NEUQ_ONE_ASSETS_ORIGIN=https://neuq-one-assets.pages.dev
```

迁移期间旧数据域名继续提供与旧客户端兼容的地图和政策路径。新版会继续读取设备已有的有效地图及政策缓存。[部署顺序](deployment.md)
