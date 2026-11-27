# 校园网络访问与 WebVPN

## 证据与当前启用范围

学校说明提供浏览器入口、CAS 登录和授权资源菜单，明确同一账号同一时间只允许一个终端。公开 WebVPN 入口的匿名检查跳转到 `/fingerprint`。当前可以使用系统浏览器完成学校提供的流程。浏览器会话由学校和浏览器管理，应用内状态页只显示应用内会话。[官方入口](https://vpn.neuq.edu.cn/) · [学校使用说明](https://xxhb.neuq.edu.cn/info/1018/1434.htm)

Data 仓库的 WebVPN 采集器要求显式提供由官方门户取得的授权教务链接。模拟覆盖了 CAS 跳转、一次表单提交、Cookie 复用和设备检查停止。测试路径与 Cookie 是占位值。Data 文档将真实 WebVPN 链接、部署网络可达性、回调及非交互访问继续列为待验证。该代码用作边界参考，Android 和 iOS 客户端均未启用原生协议适配。[Data 协议说明](https://github.com/LTCpond/neuq-one-data/blob/0851c370bb455e73835d2953306539b54bb4652d/docs/upstream.md) · [Data 模拟测试](https://github.com/LTCpond/neuq-one-data/blob/0851c370bb455e73835d2953306539b54bb4652d/internal/collector/classroom/webvpn_test.go)

生产资源表目前登记了学校公开 WebVPN 使用说明，用于 Settings 的直连浏览器入口，也可经只读客户端取得。当前没有获授权且完成真机验收的原生 WebVPN 资源。调用需 WebVPN 的未适配资源会得到明确的未支持错误，业务可引导用户打开学校门户。

## 访问路径

业务 Repository 通过 Riverpod 获取 `CampusAccessClient`，用固定资源 ID 访问。登记项包含直连 HTTPS 入口及范围、是否要求学校身份、访问策略、获授权的 VPN 入口、超时、响应分类和恢复权限。VPN 入口需来自学校门户并精确登记主机与路径，资源注册不接受用户输入的 URL。两条路径都检查每次重定向，并拒绝越界、非 HTTPS、异常端口和含歧义编码的路径。

自动选择先访问直连资源，仅在网络不可达、DNS 失败或超时时尝试该资源明确允许的已登记 WebVPN 路径。业务登录页、访问拒绝、限流、服务端错误和内容异常各有分类。仅直连策略关闭 WebVPN。优先 WebVPN 只改变已授权且有适配的资源的访问顺序。客户端只发 GET，用于经过确认的只读操作。充值、预约和其他写操作由原有或专用客户端处理。

对可切换的资源，首次直连从实际 GET 等待响应头，探测上限 2 秒，普通请求默认 10 秒。已验证可达记录有效 5 分钟，只用于调整等待时间。前台恢复、可观察到的网络接口变化或网络错误会失效相关记录。接口信息只在进程内比较，对无法观察的网络切换仍由下一次实际请求确认。

## 会话状态与清理

- `disconnected → connecting → connected` 由业务实际请求触发。当前没有账号、地址未授权、应用在后台或适配未启用时不会认证。并行请求合并到同一次认证，不同业务的租约共享会话。
- `connected → idle → connected` 发生在最后一个租约释放且在途请求完成后，以及空闲截止前有业务再次访问时。空闲时间可选立即释放或 1、5、10、15 分钟，默认 5 分钟。已有会话到期则先释放再处理新请求。
- `connected → expired / verificationRequired / error` 来自已识别的失效、额外验证或其他认证失败。明确是普通过期时允许在当前业务周期内续接一次，第二次过期或检测到其他终端挤下线后等待用户操作。业务系统自己的登录失效由该业务处理。
- 身份切换、退出、手动断开和账号不匹配立即作废本地会话或认证结果。只有适配器确认远端注销作用于该独立会话时才进入 `disconnecting` 并尝试注销，出错或超时也会关闭该会话。当前学校流程没有已确认的独立注销接口。
- App 切到后台时释放页面 VPN 租约，取消进行中的认证和业务请求，保存空闲截止时间。计时器只在前台运行，恢复时按实际时间检查截止，不主动连接。进程销毁后内存会话不保留，远端会话由学校过期。

学校账号、CAS、教务、校园卡和 WebVPN 各有自己的用途。应用内 WebVPN 适配需提供专用 HTTP 客户端及内存 Cookie 管理，遵守域名、路径、Secure 和过期属性。接口提供按账号读取既有 Android 加密凭据的入口，仅当适配器正常验证后明确需要密码才应使用，每次认证最多读取一次。iOS 继续不保存密码。现有教务 CAS 票据只用于已经实现并核实的服务，原生 WebVPN 尚无受支持的 CAS 或浏览器 Cookie 共享路径。

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

## 真机验收边界

自动化测试验证策略、请求范围、模拟认证、失败停止、并发、租约、后台截止、旧账号取消和隔离注销。启用任何真实原生适配前，需使用获授权账号验证官方 CAS 与设备检查，确认资源 URI、Cookie 作用域、过期与挤下线的明确观测信号。还需检查独立注销行为、校内外 DNS 和网络切换、Android/iOS 的官方浏览器回跳。真实凭据、设备检查数据和 Cookie 均不得进入仓库或日志。
