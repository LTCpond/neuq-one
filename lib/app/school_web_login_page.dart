import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../core/auth/neuq_login_protocol.dart';
import '../core/auth/school_auth.dart';

class SchoolWebLoginPage extends StatefulWidget {
  const SchoolWebLoginPage({super.key, this.expectedSubject});

  final String? expectedSubject;

  @override
  State<SchoolWebLoginPage> createState() => _SchoolWebLoginPageState();
}

class _SchoolWebLoginPageState extends State<SchoolWebLoginPage> {
  late final WebViewController _controller;
  late final WebViewWidget _webView;
  bool _loading = true;
  bool _checking = false;
  bool _finished = false;
  bool _wrongAccount = false;
  String? _error;
  Uri? _document;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
    final platform = _controller.platform;
    _webView = platform is AndroidWebViewController
        ? WebViewWidget.fromPlatformCreationParams(
            params: AndroidWebViewWidgetCreationParams(
              controller: platform,
              displayWithHybridComposition: true,
            ),
          )
        : WebViewWidget(controller: _controller);
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _navigate,
          onPageStarted: (url) {
            if (!mounted || _finished) return;
            setState(() {
              _loading = true;
              _error = null;
              _wrongAccount = false;
              _document = Uri.tryParse(url);
            });
          },
          onPageFinished: (url) {
            if (!mounted || _finished) return;
            final document = Uri.tryParse(url);
            setState(() {
              _loading = false;
              _document = document;
            });
            if (document == null || !isAcademicDocument(document)) return;
            unawaited(_checkIdentity());
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == false) return;
            _showError('学校页面加载失败，请检查网络后重试。');
          },
        ),
      );
      await _controller.loadRequest(schoolWebEntry);
    } catch (_) {
      _showError('无法启动学校网页，请重试。');
    }
  }

  NavigationDecision _navigate(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;
    if (!request.isMainFrame && uri.toString() == 'about:blank') {
      return NavigationDecision.navigate;
    }
    switch (schoolNavigation(uri)) {
      case SchoolNavigation.allow:
        return NavigationDecision.navigate;
      case SchoolNavigation.upgrade:
        if (request.isMainFrame && mounted) {
          unawaited(_load(uri.replace(scheme: 'https', port: 443)));
        }
        return NavigationDecision.prevent;
      case SchoolNavigation.block:
        if (request.isMainFrame) _showError('此地址不在已核实的校方登录范围内。');
        return NavigationDecision.prevent;
    }
  }

  Future<void> _load(Uri uri) async {
    try {
      await _controller.loadRequest(uri);
    } catch (_) {
      _showError('学校页面暂时无法打开，请重试。');
    }
  }

  void _showError(String message) {
    if (!mounted || _finished) return;
    setState(() {
      _loading = false;
      _error = message;
    });
  }

  Future<void> _checkIdentity({bool explain = false}) async {
    if (_checking || _finished || _loading) return;
    setState(() => _checking = true);
    try {
      final current = Uri.tryParse(await _controller.currentUrl() ?? '');
      if (current == null || !isAcademicDocument(current)) {
        if (explain) _showError('请先完成学校认证并进入教务网页。');
        return;
      }
      final evidence = await _controller.runJavaScriptReturningResult(
        schoolIdentityProbe,
      );
      final after = Uri.tryParse(await _controller.currentUrl() ?? '');
      if (!mounted || _finished || _loading || after != current) return;

      final subject = schoolSubjectFromEvidence(current, evidence);
      if (subject == null) {
        if (explain) {
          _showError('暂未识别到已登录的学生账号，请返回教务首页后重试。');
        }
        return;
      }
      if (widget.expectedSubject != null && subject != widget.expectedSubject) {
        setState(() => _wrongAccount = true);
        _showError('请使用当前工作台对应的学校账号。');
        return;
      }
      if (ModalRoute.of(context)?.isCurrent != true) return;
      _finished = true;
      Navigator.of(context).pop(SchoolSession(subject: subject));
    } catch (_) {
      if (explain) _showError('暂时无法验证教务账号，请刷新页面后重试。');
    } finally {
      if (mounted && !_finished) setState(() => _checking = false);
    }
  }

  Future<void> _switchAccount() async {
    try {
      await WebViewCookieManager().clearCookies();
      if (mounted) await _load(schoolWebEntry);
    } catch (_) {
      _showError('暂时无法切换账号，请稍后重试。');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('东秦登录'),
      actions: [
        IconButton(
          onPressed: _loading ? null : () => _load(schoolWebEntry),
          tooltip: '重开登录页',
          icon: const Icon(Icons.refresh),
        ),
        PopupMenuButton<Uri>(
          tooltip: '选择学校登录入口',
          onSelected: (uri) => _load(uri),
          itemBuilder: (context) => [
            PopupMenuItem(value: schoolWebEntry, child: const Text('统一身份认证')),
            PopupMenuItem(
              value: schoolAcademicLogin,
              child: const Text('教务账号登录'),
            ),
          ],
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (_document case Uri(host: final host) when host.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: Text(host, style: Theme.of(context).textTheme.labelMedium),
            ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(child: _webView),
          if (_wrongAccount)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.tonal(
                onPressed: _switchAccount,
                child: const Text('切换教务账号'),
              ),
            )
          else if (_document case final Uri document
              when isAcademicDocument(document))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.tonal(
                onPressed: _loading || _checking
                    ? null
                    : () => _checkIdentity(explain: true),
                child: Text(_checking ? '正在验证…' : '验证并进入'),
              ),
            ),
        ],
      ),
    ),
  );
}
