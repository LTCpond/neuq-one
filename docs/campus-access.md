# 校园网络访问与 WebVPN

## 证据与当前启用范围

学校说明提供浏览器入口、CAS 登录和授权资源菜单，明确同一账号同一时间只允许一个终端。公开 WebVPN 入口的匿名检查跳转到 `/fingerprint`。当前可以使用系统浏览器完成学校提供的流程。浏览器会话由学校和浏览器管理，应用内状态页只显示应用内会话。[官方入口](https://vpn.neuq.edu.cn/) · [学校使用说明](https://xxhb.neuq.edu.cn/info/1018/1434.htm)

Data 仓库的 WebVPN 采集器要求显式提供由官方门户取得的授权教务链接。其模拟覆盖 CAS 跳转、表单提交、Cookie 复用和设备检查停止。测试路径与 Cookie 是占位值。Data 文档将真实 WebVPN 链接、部署网络可达性、回调及非交互访问列为待验证。[Data 协议说明](https://github.com/LTCpond/neuq-one-data/blob/main/docs/upstream.md) · [Data 模拟测试](https://github.com/LTCpond/neuq-one-data/blob/main/internal/collector/classroom/webvpn_test.go)

生产资源表登记了学校公开 WebVPN 使用说明，用于设置页的直连浏览器入口，也可经只读客户端取得。`webVpnProtocolProvider` 生产值为 `null`。获得校方许可和首个经真机确认的授权只读入口后，才能配置原生适配并登记对应资源。

## 访问路径

业务 Repository 通过 Riverpod 获取 `CampusAccessClient`，用固定资源 ID 访问。登记项包含直连 HTTPS 入口及范围、是否要求学校身份、访问策略、获授权的 VPN 入口、超时、响应分类和恢复权限。VPN 入口需来自学校门户并精确登记主机与路径，资源注册不接受用户输入的 URL。两条路径都检查每次重定向，并拒绝越界、非 HTTPS、异常端口和含歧义编码的路径。

自动选择先发实际直连请求。DNS 解析失败、连接失败、网络不可达或等待响应头超时才触发已登记的 WebVPN 路径。收到响应头后的传输中断、业务登录页、HTTP 403、限流、服务端错误和内容异常各有失败分类。资源的 `directOnly`、`preferDirect`、`vpnOnly` 和显式用户偏好优先于缓存。统一访问层只发 GET，限已确认的只读操作。充值和预约继续由原有业务处理。

对可切换的资源，首次实际 GET 等待响应头的探测上限为 2 秒，普通请求默认 10 秒。直连成功按直连处理。直连不可达且 WebVPN 成功后，同一资源和同一网络在接下来 5 分钟优先复用 WebVPN。命中 WebVPN 路径不会延长直连重新探测的期限。缓存路径失败后作废，切换网络或进入后台时清理，恢复前台时重新检查。Android 比较系统默认网络句柄，其他平台使用可观察的接口变化。无法识别网络时跳过路径缓存。网络标识仅用于内存比较，可达性始终由目标响应决定。

## 原生认证与浏览器验证

`NeuqWebVpnProtocol` 从官方门户开始。配置项必须提供经核实的 CAS 入口、回调地址和能确认当前账号的门户响应规则。适配器只跟随匹配的学校跳转，遇到 `/fingerprint`、验证码或额外认证即停止。它与教务共用 CAS 表单解析和密码加密，在核实密码表单及提交地址后，通过 `WebVpnAuthentication.readRemembered()` 最多读取一次已授权凭据。回调完成后，还要从可信门户响应取得学校账号并匹配当前身份。

每个应用内 WebVPN 会话有独立的 HTTP 客户端。内存 Cookie 按域名、路径、Secure 和有效期管理，关闭会话时释放；密码提交发生在核实过的学校统一认证 HTTPS 地址。密码错误与限流触发至少五分钟自动认证停顿，重新连接需用户操作。现有密码旧记录首次用于 WebVPN 前需要明确授权，iOS 只使用浏览器完成需要密码的验证。删除密码会取消在途认证，旧查询结果无法继续提交密码。

只读页面可用 `CampusResourcePanel` 加载资源、释放页面租约及显示重试和身份验证入口。同一时间只显示一个验证对话框。用户取消后可以主动再次发起。验证按钮使用注册的学校浏览器资源入口，缺少对应地址时打开官方门户供用户选择资源。系统浏览器继续处理校方验证及访问，返回 App 时原生状态保持由独立原生会话决定。当前没有经学校确认的浏览器会话交接。

## 会话状态与清理

- `disconnected → connecting → connected` 由业务实际请求触发。当前没有账号、地址未授权、应用在后台或适配未启用时不会认证。并行请求合并到同一次认证，不同业务的租约共享会话。
- `connected → idle → connected` 发生在最后一个租约释放且在途请求完成后，以及空闲截止前有业务再次访问时。空闲时间可选立即释放或 1、5、10、15 分钟，默认 5 分钟。已有会话到期则先释放再处理新请求。
- `connected → expired / verificationRequired / error` 来自已识别的失效、额外验证或其他认证失败。明确是普通过期时允许在当前业务周期内续接一次，第二次过期或检测到其他终端挤下线后等待用户操作。业务系统自己的登录失效由该业务处理。
- 身份切换、退出、手动断开和账号不匹配立即作废本地会话或认证结果。只有适配器确认远端注销作用于该独立会话时才进入 `disconnecting` 并尝试注销，出错或超时也会关闭该会话。当前学校流程没有已确认的独立注销接口。
- App 切到后台时释放页面 VPN 租约，取消进行中的认证和校园访问请求，保存空闲截止时间。计时器只在前台运行，恢复时按实际时间检查截止。进程销毁后远端会话由学校过期。

诊断只记录固定资源、路由、阶段、耗时、状态码和脱敏分类。App 保留本地缓存和已验证身份，WebVPN 错误不会变更教务连接状态。

## 后续只读业务示例

1. 先取得学校接入许可和授权资源链接，审查可验证的重定向和响应，再在 `campusResourcesProvider` 中登记。需要 WebVPN 时提供通过验收的 `WebVpnProtocol` 实现；在确认前保留官方浏览器入口。
2. 只有页面实际可见并需要访问时才开始业务用量。GoRouter 分支可能留存页面，需在路由被覆盖、分支失焦、业务取消及销毁时关闭 `CampusAccessUse`。一次性读取可省略它，由客户端释放临时租约。
3. 解析并校验响应后，在账号隔离的数据库事务中、写入前调用 `ensureCurrent()`。发生取消或任何失败时保留旧快照。

```dart
final access = ref.read(campusAccessClientProvider);
final use = access.openUse();
try {
  // 使用已登记的资源。公开说明只允许直连。
  final result = await access.read(CampusResourceId.webVpnGuide, use: use);
  final validated = parseGuide(result.response.bytes);
  await database.transaction(() async {
    result.ensureCurrent();
    await saveValidatedSnapshot(validated);
  });
} finally {
  use.close();
}
```

## Android 真机验收

1. 用 `flutter build apk --debug` 构建并安装 NEUQ One Dev。打开「我的 → WebVPN」，确认状态为「未连接」，打开官方门户，用本人学校账号完成学校要求的验证。选择本人获授权的只读资源。返回 App 后确认原生状态仍为「未连接」。
2. 在 IPv4-only 网络中，确认同一资源的官方直连地址不可达、通过官方门户可访问。切换到目标实际可达的网络，确认直连恢复。保留可达性结论和脱敏失败分类。
3. 在获校方接入许可后，核实 CAS 入口、提交地址、回调、账户证明及 Cookie 属性，登记该资源的官方直连和官方 VPN 入口。仅在受控的测试构建中配置适配器，检查直连成功、不可达后回退、同网重复访问复用、Wi-Fi 与移动网络切换及五分钟后重测。
4. 分别测试未保存密码、旧密码补充授权、删除密码时认证在途，以及学校设备验证、验证码和额外认证。确认取消后可手动重试。若学校支持浏览器会话交接，单独核实学校提供的机制和账号绑定后再启用自动续接。
5. 核实学校可观察的会话过期和被另一终端替换信号。分别确认只读请求最多自动续接一次、被替换后等待手动重新连接，并检查后台、恢复前台、退出及切换账号。独立远端注销需另有校方证据。
6. 让 WebVPN 访问失败，检查教务、课表、成绩及公共资源仍可访问或读取已有离线数据。诊断记录仅包含固定资源 ID、路径、阶段、耗时、状态码和分类；验收材料不得记录密码、Cookie、票据或真实学生数据。

`test/campus_access_test.dart`、`test/neuq_webvpn_protocol_test.dart` 和 `test/neuq_client_test.dart` 使用模拟数据覆盖选路、认证与教务回归。学校环境的步骤需要在设备上单独验收。
