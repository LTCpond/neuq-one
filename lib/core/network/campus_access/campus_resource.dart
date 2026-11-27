import 'dart:async';
import 'dart:typed_data';

const officialWebVpnUrl = 'https://vpn.neuq.edu.cn/';
const officialWebVpnGuide = 'https://xxhb.neuq.edu.cn/info/1018/1434.htm';
const officialWebVpnHost = 'vpn.neuq.edu.cn';

enum CampusResourceId { webVpnGuide, academic }

enum CampusResourcePolicy { directOnly, preferDirect, vpnOnly }

enum CampusAccessPreference {
  automatic('自动选择'),
  directOnly('仅直接访问'),
  preferVpn('优先 WebVPN');

  const CampusAccessPreference(this.label);
  final String label;
}

enum CampusAccessRoute { direct, webVpn }

enum CampusAccessFailure implements Exception {
  unreachable('无法连接校园服务，请检查网络后重试。'),
  dns('无法解析校园服务地址，请检查网络后重试。'),
  timeout('校园服务请求超时，请稍后重试。'),
  businessSessionExpired('校园业务登录已过期，请重新登录该服务。'),
  vpnSessionExpired('WebVPN 会话已过期，请按需重新连接。'),
  vpnDisplaced('WebVPN 会话可能已被其他终端断开，请确认后重新连接。'),
  unauthorized('学校未授权访问此资源。'),
  credentialsRequired('请在学校官方 WebVPN 门户登录。'),
  authenticationRejected('学校拒绝了 WebVPN 登录，请在官方门户确认账号状态。'),
  verificationRequired('请在学校官方 WebVPN 门户完成额外验证。'),
  accountMismatch('WebVPN 会话与当前学校账号不匹配。'),
  rateLimited('学校暂时限制了请求，请稍后重试。'),
  server('校园服务暂时异常，请稍后重试。'),
  invalidResponse('校园服务返回了无法识别的内容。'),
  unsafeEndpoint('校园服务地址超出了已核实的访问范围。'),
  unsupported('该资源的应用内 WebVPN 访问尚未适配，请使用官方门户。'),
  preferenceBlocked('当前访问策略仅允许直连，此资源需要 WebVPN。'),
  cancelled('校园访问已取消。');

  const CampusAccessFailure(this.message);
  final String message;

  bool get isReachabilityFailure =>
      this == unreachable || this == dns || this == timeout;
}

class CampusAccessLimits {
  static const directProbe = Duration(seconds: 2);
  static const request = Duration(seconds: 10);
  static const reachability = Duration(minutes: 5);
  static const idleMinutes = 5;
  static const idleChoices = [0, 1, 5, 10, 15];
  static const authentication = Duration(seconds: 30);
  static const logout = Duration(seconds: 5);
  static const redirects = 5;
  static const responseBytes = 2 * 1024 * 1024;
}

/// Each scope is a single HTTPS host and a path or path subtree. Registration
/// is app code, so a user-supplied URL cannot become a proxy target.
class CampusUrlScope {
  const CampusUrlScope(this.host, this.path, {this.subtree = false});

  final String host;
  final String path;
  final bool subtree;

  bool allows(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.host != host ||
        uri.port != 443 ||
        uri.authority.contains('@') ||
        uri.hasFragment ||
        uri.path.contains('%') ||
        uri.path.contains(r'\')) {
      return false;
    }
    final base = subtree && path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    return (uri.path == base && base.isNotEmpty) ||
        subtree && uri.path.startsWith('$base/');
  }
}

class CampusEndpoint {
  const CampusEndpoint({
    required this.entry,
    required this.scope,
    this.businessLogin,
    this.vpnLogin,
    this.classify,
  });

  final Uri entry;
  final CampusUrlScope scope;
  final CampusUrlScope? businessLogin;
  final CampusUrlScope? vpnLogin;
  final CampusAccessFailure? Function(CampusResponse)? classify;
}

class CampusResource {
  const CampusResource({
    required this.direct,
    this.policy = CampusResourcePolicy.preferDirect,
    this.requiresAuthentication = false,
    this.allowsWebVpn = false,
    this.webVpn,
    this.allowVpnRecovery = true,
    this.timeout = CampusAccessLimits.request,
  });

  final CampusEndpoint direct;
  final CampusResourcePolicy policy;
  final bool requiresAuthentication;
  final bool allowsWebVpn;

  /// An exact authorized resource entry obtained from the school portal.
  final CampusEndpoint? webVpn;
  final bool allowVpnRecovery;
  final Duration timeout;
}

class CampusResponse {
  const CampusResponse(this.status, this.headers, this.bytes);

  final int status;
  final Map<String, String> headers;
  final Uint8List bytes;
}

class CampusCancellation {
  bool _cancelled = false;
  final _listeners = <void Function()>{};

  void check() {
    if (_cancelled) throw CampusAccessFailure.cancelled;
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = _listeners.toList();
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  void Function() listen(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
    return () => _listeners.remove(listener);
  }

  Future<T> untilCancelled<T>(Future<T> operation) {
    final result = Completer<T>();
    final unlisten = listen(() {
      if (!result.isCompleted) {
        result.completeError(CampusAccessFailure.cancelled);
      }
    });
    operation.then(
      (value) {
        unlisten();
        if (!result.isCompleted) result.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        unlisten();
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    return result.future;
  }
}
