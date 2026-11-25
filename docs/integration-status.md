# 东秦数据接入

| 能力 | 当前实现 | 启用条件 |
| --- | --- | --- |
| 统一身份认证 | App 内通过官方网页登录。刷新教务数据时，若教务会话已失效，会尝试用仍有效的统一认证会话完成官方回跳，再核对当前账号 | 校方要求重新认证时，在 App 内打开官方登录页；离线数据可继续查看 |
| 课表 | 复用教务网页会话读取当前学期个人课表和学期列表，按账号保存验证通过的快照 | 经教务认证且账号可查看本人课表。真机数据待验收 |
| 成绩 | 每次进入读取本人历史成绩。学期 GPA 缺少时按入学年级办法计算 | 已收到 Android 真机成绩显示反馈。新版计算和显示待复验 |
| 空教室 | 在已登录教务会话中按六个时段查询，核对网页回显和分页信息。异常时段使用教务表单按楼栋补查 | 已收到 Android 0.1.8 真机各时段查询成功的反馈 |
| 校园卡 | 进入首页或下拉刷新时使用官方网页更新该账号可见余额。按账号加密保存最近一次读取结果。校方充值页可跳转官方微信或支付宝收银台 | 真机已显示官方校园卡网页。App 内充值跳转待真机验证 |
| 校园邮箱 | 使用 SSL/TLS 的 IMAP/SMTP 接入分校邮箱。在 App 内查看文件夹和邮件、搜索、收发及保存附件。客户端授权码按校内账号存入系统安全存储 | 在网页上启用 IMAP/SMTP 并生成客户端授权码 |
| 就业活动 | 同步公开就业信息网首页的最新宣讲会和招聘会，缓存有效期 30 分钟，刷新失败时保留上次结果 | 浏览器可打开官方详情和完整列表 |
| 校园网站 | 教务系统、一网通办、校园网、WebVPN、校园地图在系统浏览器打开 | 按各官方站点的访问和认证要求 |

## 官方依据

校园卡在 Android 打开系统照片选择器，将用户选中的图片交给学校网页；iOS 由 WebKit 处理网页选图。相机请求仅在前台显示校园卡页面时处理。校园卡工具栏可打开微信，扫码在学校「东秦校园卡」小程序内完成。

- [统一身份认证帮助](https://ids.neuq.edu.cn/authserver/help/index.html)说明第三方应用须经资格审查。[信息化办](https://xxhb.neuq.edu.cn/)提供统一身份认证和公共基础数据接入申请入口。
- 登录入口采用[教务处](https://jwc.neuq.edu.cn/)的一网通办入口及公开教务登录页。原站会返回 HTTP 重定向，App 仅对已核实的登录和返回路径升级为 HTTPS，保留原 CAS 参数。若升级后校方无法完成回跳，可在登录页菜单尝试官方教务账号入口。
- [东北大学秦皇岛分校教学作息时间表](https://jwc.neuq.edu.cn/__local/7/A3/74/30B5B2E34A83B7421C3F9420A1B_C5316155_F1E8.pdf)提供 12 节上下课时间。
- 教务学期缺少日期时使用对应学年的学校校历。[2024–2025 学年](https://jwc.neuq.edu.cn/__local/D/D9/F7/9CF57A987309D181E978B236AB9_FEC9E4A8_75240.pdf) · [2025–2026 学年](https://jwc.neuq.edu.cn/__local/0/54/97/9B9DDB54B6F8ECA0DF7EDA36F99_42399B7E_74D28.pdf) · [2026–2027 学年](https://jwc.neuq.edu.cn/info/1077/3582.htm)
- [东秦教〔2025〕17 号](https://jwc.neuq.edu.cn/__local/8/D5/BA/B14A577547B0111B7BA1B241E2B_7DEA94A5_3523D.pdf)和[东秦教〔2019〕16 号](https://jwc.neuq.edu.cn/__local/B/41/42/D64F2600C48B924B4A9C4501BA8_BFEF2336_2FEF6.pdf)分别用于对应年级的本地绩点计算。
- 网页入口来自[教务系统](https://jwxt.neuq.edu.cn/eams/localLogin.action)、[学校官网](https://www.neuq.edu.cn/)、[WebVPN](https://vpn.neuq.edu.cn/)和[迎新网学校地图](https://yx.neuq.edu.cn/shgl/xxdt.htm)。
- [一网通办](https://eone.neuq.edu.cn/)的「推荐服务 → 校园卡」跳转到[校园卡网页](https://cardmobile.neuq.edu.cn/home/toHomePage)，未登录时由学校统一身份认证处理。[学校校园卡指南](https://xxhb.neuq.edu.cn/info/1018/2223.htm)
- [校园邮箱入口](https://mail.neuq.edu.cn/)公布了加密邮件端口。[学生邮箱申请使用指南](https://xxhb.neuq.edu.cn/info/1018/1573.htm)列出了分校学生邮箱适用范围和开通方式。
- [就业信息网](https://job.neuq.edu.cn/)公开发布[宣讲会](https://job.neuq.edu.cn/teachin/index)和[招聘会](https://job.neuq.edu.cn/jobfair)安排。
- 校园卡 WebView 从学校页面进入支付服务的 HTTPS 收银台，由校方和支付平台处理订单及付款确认。Android 将收银台发出的唤起链接交给对应客户端。[微信 H5 支付指引](https://pay.wechatpay.cn/doc/v3/partner/4012085683) · [支付宝唤起链接说明](https://aipay.alipay.com/docs/vibe-pay/nowpay/direct/api-list/purchase_create.html)

## 设计参考

周课表参考拾光课程表的星期列、节次轴和课程色块布局。[拾光课程表](https://sgschedule.jursin.top/)

BUCT One 的公开 README 介绍了北化专有认证适配、共享会话及分域快照的设计。NEUQ One采用独立的认证和读数据接口，缓存写入前验证数据，并在刷新失败时保留上次快照。[BUCT One](https://github.com/STAR-10086/buct-one)

空教室参考公开项目中的教务请求字段和结果表头。NEUQ One使用 Dart 实现全楼栋查询及结果分组，通过学生已登录的本机教务网页获取结果。[查询格式参考](https://github.com/wy723161060/neuq-classroom-query)

NEUQ One用 Dart 解析学生本人在学校网页上有权限查看的结果。个人课表路径和数据结构参考拾光课程表的东秦适配，空教室表单参考 Juns 的东秦脚本，历史成绩使用树维本科历史成绩页面路径。请求以校方会话权限为准，校方拒绝、超时或无法解析返回时保留有效快照。[东秦课表参考](https://github.com/ShiGuangSchedule/shiguang_warehouse/blob/main/resources/NEUQ/neuq.js) · [东秦空教室参考](https://greasyfork.org/zh-CN/scripts/462970-%E7%A9%BA%E6%95%99%E5%AE%A4%E8%A1%A8) · [树维历史成绩参考](https://greasyfork.org/en/scripts/471378-%E4%B8%9C%E5%8C%97%E5%A4%A7%E5%AD%A6%E7%BB%A9%E7%82%B9%E5%B0%8F%E5%8A%A9%E6%89%8B/code)
