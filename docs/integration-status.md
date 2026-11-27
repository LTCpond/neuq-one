# 东秦数据接入

| 能力 | 当前实现 | 启用条件 |
| --- | --- | --- |
| 统一身份认证 | 在 App 表单使用本人学校账号。Android 用户可选择在本机加密记住密码以便续登 | 校方要求额外验证时可在系统浏览器访问官方教务。原生登录有模拟回归覆盖，真实账号待验收 |
| 课表 | 使用已验证的教务会话读取当前学期个人课表和学期列表，按账号保存验证通过的快照 | 经教务认证且账号可查看本人课表。真机数据待验收 |
| 成绩 | 每次进入读取本人历史成绩。学期 GPA 缺少时按入学年级办法计算 | 已收到 Android 真机成绩显示反馈。新版计算和显示待复验 |
| 空教室 | 从 NEUQ One Data 读取北京时间七日快照，切换日期或楼栋时使用已加载数据。设备缓存保留完整时段状态与采集时间 | 公共 API 无需学校会话。迁移后的客户端待真机复验 |
| 校园地图 | 从 NEUQ One Assets 下载静态 PNG，在应用内缩放和全屏查看。使用设备文件缓存和 HTTP 条件请求 | 首次查看需要联网且地图已发布。下载成功后可离线查看 |
| 学校政策 | 从 NEUQ One Assets 读取政策目录，在应用内预览并保存原文 PDF | 已缓存的目录和同版本原文可离线查看 |
| App 检查更新 | 从 NEUQ One Assets 读取正式版本清单，比对已安装包的版本 | 需要联网，发现新版本时可打开 GitHub Release 页面 |
| 校园卡 | 打开页面或更新余额时，可用已有统一认证会话换取校园卡专用票据。余额按账号加密保存。校方充值页可跳转官方微信或支付宝收银台 | 校方要求额外验证时可在校园卡页完成。免重复登录和 App 内充值跳转待真机验证 |
| 校园邮箱 | 使用 TLS 加密的 IMAP/SMTP 接入东北大学学生邮箱。在 App 内查看文件夹和邮件、搜索、收发及保存附件。客户端专用密码按校内账号存入系统安全存储 | 在学校邮箱网页启用 IMAP/SMTP 并生成客户端专用密码 |
| 就业活动 | 同步公开就业信息网首页的最新宣讲会和招聘会，缓存有效期 30 分钟，刷新失败时保留上次结果 | 浏览器可打开官方详情和完整列表 |
| 校园网站 | 教务系统、一网通办、校园网、校外远程资源访问系统在系统浏览器打开 | 按各官方站点的访问和认证要求 |
| CampusAccess | 固定只读资源的直连和 WebVPN 选择、范围校验、脱敏诊断。注册了学校公开 WebVPN 使用说明的直连入口 | 直连说明来源为学校公开网站。原生 VPN 路由使用模拟服务测试，未注册已授权的真实 VPN 资源 |
| WebVPN | 官方浏览器门户和应用内设置。原生会话管理支持按账号隔离、按需认证、取消和空闲清理 | 原生协议适配默认关闭。需校方确认受支持的原生流程与资源范围，并验证单终端行为 |

## 官方依据

校园卡在 Android 打开系统照片选择器，将用户选中的图片交给学校网页；iOS 由 WebKit 处理网页选图。相机请求仅在前台显示校园卡页面时处理。校园卡工具栏可打开微信，扫码在学校「东秦校园卡」小程序内完成。

学校政策收录维护者提供的分校政策原件。PDF 和 `index.json` 一起放在 Data 仓库的 `assets/policies/`，随静态资源发布到 `/assets/policies/`。客户端先读取本地目录，再尝试刷新。PDF 以目录中的 SHA-256 校验版本，校验通过后才写入缓存。请求或校验失败时保留已有缓存。

- [统一身份认证帮助](https://ids.neuq.edu.cn/authserver/help/index.html)说明第三方应用须经资格审查。[信息化办](https://xxhb.neuq.edu.cn/)提供统一身份认证和公共基础数据接入申请入口。
- 登录从[教务系统](https://jwxt.neuq.edu.cn/eams/homeExt.action)进入校方统一认证。App 仅对已核实的登录和返回路径升级为 HTTPS，保留原 CAS 参数。校方要求额外验证或流程变化时可在系统浏览器打开教务查询，浏览器会话独立。
- [东北大学秦皇岛分校教学作息时间表](https://jwc.neuq.edu.cn/__local/7/A3/74/30B5B2E34A83B7421C3F9420A1B_C5316155_F1E8.pdf)提供 12 节上下课时间。
- 教务学期缺少日期时使用对应学年的学校校历。[2024–2025 学年](https://jwc.neuq.edu.cn/__local/D/D9/F7/9CF57A987309D181E978B236AB9_FEC9E4A8_75240.pdf) · [2025–2026 学年](https://jwc.neuq.edu.cn/__local/0/54/97/9B9DDB54B6F8ECA0DF7EDA36F99_42399B7E_74D28.pdf) · [2026–2027 学年](https://jwc.neuq.edu.cn/info/1077/3582.htm)
- [东秦教〔2025〕17 号](https://jwc.neuq.edu.cn/__local/8/D5/BA/B14A577547B0111B7BA1B241E2B_7DEA94A5_3523D.pdf)和[东秦教〔2019〕16 号](https://jwc.neuq.edu.cn/__local/B/41/42/D64F2600C48B924B4A9C4501BA8_BFEF2336_2FEF6.pdf)分别用于对应年级的本地绩点计算。
- 网页入口来自[教务系统](https://jwxt.neuq.edu.cn/eams/localLogin.action)、[学校官网](https://www.neuq.edu.cn/)和[WebVPN](https://vpn.neuq.edu.cn/)。
- 官方说明确认在浏览器使用 CAS 登录、从门户选择获授权资源，同一账号同时只能登录一个终端。匿名访问门户观察到设备检查跳转。应用内不会尝试模拟该检查。WebVPN 的授权资源路径、Cookie 及独立注销方式仍待验收。[学校使用说明](https://xxhb.neuq.edu.cn/info/1018/1434.htm) · [CampusAccess 验证边界](campus-access.md)
- 校园地图的资源路径和发布流程见 Data 仓库。[静态资源与校园地图](https://github.com/LTCpond/neuq-one-data/blob/main/docs/static-assets.md)
- [一网通办](https://eone.neuq.edu.cn/)的「推荐服务 → 校园卡」跳转到[校园卡网页](https://cardmobile.neuq.edu.cn/home/toHomePage)，未登录时由学校统一身份认证处理。[学校校园卡指南](https://xxhb.neuq.edu.cn/info/1018/2223.htm)
- 东北大学学生邮箱使用 `@mails.neu.edu.cn`，迁移上云前开通的账号继续使用 `@stu.neu.edu.cn`。[学生邮箱注册和登录指南](https://xwb.neu.edu.cn/10178/list.htm)
- 校园邮箱在系统浏览器打开官方入口。App 内收发使用 Coremail 云邮箱的 `uni-edu.icoremail.net`，通过 TLS 连接 IMAP 993 和 SMTP 465。已验证两项服务的 TLS 握手和协议响应，真实账号收发待验收。[东北大学学生邮箱](https://mails.neu.edu.cn/) · [Coremail 客户端配置指南](https://support.coremail.cn/Q-11/100003.html)
- [就业信息网](https://job.neuq.edu.cn/)公开发布[宣讲会](https://job.neuq.edu.cn/teachin/index)和[招聘会](https://job.neuq.edu.cn/jobfair)安排。
- 校园卡 WebView 从学校页面进入支付服务的 HTTPS 收银台，由校方和支付平台处理订单及付款确认。Android 将收银台发出的唤起链接交给对应客户端。[微信 H5 支付指引](https://pay.wechatpay.cn/doc/v3/partner/4012085683) · [支付宝唤起链接说明](https://aipay.alipay.com/docs/vibe-pay/nowpay/direct/api-list/purchase_create.html)

## 设计参考

周课表参考拾光课程表的星期列、节次轴和课程色块布局。[拾光课程表](https://sgschedule.jursin.top/)

BUCT One 的公开 README 介绍了北化专有认证适配、共享会话及分域快照的设计。NEUQ One采用独立的认证和读数据接口，缓存写入前验证数据，并在刷新失败时保留上次快照。[BUCT One](https://github.com/STAR-10086/buct-one)

NEUQ One 用 Dart 解析学生本人在学校网页上有权限查看的个人课表和历史成绩。请求以校方会话权限为准，校方拒绝、超时或无法解析返回时保留有效快照。[东秦课表参考](https://github.com/ShiGuangSchedule/shiguang_warehouse/blob/main/resources/NEUQ/neuq.js) · [树维历史成绩参考](https://greasyfork.org/en/scripts/471378-%E4%B8%9C%E5%8C%97%E5%A4%A7%E5%AD%A6%E7%BB%A9%E7%82%B9%E5%B0%8F%E5%8A%A9%E6%89%8B/code)
