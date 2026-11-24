import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../core/network/official_browser.dart';
import '../../../core/widgets/screen.dart';
import '../data/campus_card_balance.dart';
import '../data/campus_card_camera.dart';
import '../data/campus_card_payment.dart';
import '../data/campus_card_protocol.dart';

class CampusCardPage extends ConsumerWidget {
  const CampusCardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(campusCardRepositoryProvider);
    if (repository != null) return _CampusCardWebView(repository: repository);
    return CampusScreen(
      title: '校园卡',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: StatePanel(
          '打开学校校园卡',
          '可通过学校统一身份认证查看余额和卡务服务。',
          icon: Icons.credit_card_outlined,
          action: FilledButton(
            onPressed: () =>
                openOfficialPage(context, campusCardEntry.toString()),
            child: const Text('在浏览器打开'),
          ),
        ),
      ),
    );
  }
}

class _CampusCardWebView extends ConsumerStatefulWidget {
  const _CampusCardWebView({required this.repository});

  final CampusCardRepository repository;

  @override
  ConsumerState<_CampusCardWebView> createState() => _CampusCardWebViewState();
}

class _CampusCardWebViewState extends ConsumerState<_CampusCardWebView> {
  late final WebViewController _controller;
  late final WebViewWidget _view;
  Uri? _document;
  var _navigation = 0;
  var _loading = true;
  var _reading = false;
  var _openingWallet = false;
  var _requestingCamera = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController(
      onPermissionRequest: (request) => unawaited(_requestCamera(request)),
    );
    final platform = _controller.platform;
    _view = platform is AndroidWebViewController
        ? WebViewWidget.fromPlatformCreationParams(
            params: AndroidWebViewWidgetCreationParams(
              controller: platform,
              displayWithHybridComposition: true,
            ),
          )
        : WebViewWidget(controller: _controller);
    unawaited(_start());
  }

  bool _canRequestCamera(int navigation) =>
      mounted &&
      navigation == _navigation &&
      ModalRoute.of(context)?.isCurrent == true &&
      _document != null &&
      isCampusCardPage(_document!);

  Future<void> _requestCamera(WebViewPermissionRequest request) async {
    final navigation = _navigation;
    if (_requestingCamera ||
        !_canRequestCamera(navigation) ||
        request.types.length != 1 ||
        !request.types.contains(WebViewPermissionResourceType.camera)) {
      await request.deny();
      return;
    }
    _requestingCamera = true;
    try {
      final platform = _controller.platform;
      final allowed = await ref
          .read(campusCardCameraProvider)
          .request(
            androidWebViewIdentifier: platform is AndroidWebViewController
                ? platform.webViewIdentifier
                : null,
          );
      if (!_canRequestCamera(navigation)) {
        await request.deny();
      } else if (allowed) {
        await request.grant();
      } else {
        await request.deny();
        _report('扫一扫需要相机权限，请在系统设置中允许相机权限后重试。');
      }
    } catch (_) {
      await request.deny();
      if (_canRequestCamera(navigation)) {
        _report('相机暂时无法打开，请检查权限后重试。');
      }
    } finally {
      _requestingCamera = false;
    }
  }

  Future<void> _start() async {
    try {
      await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await _controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigationRequest,
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _navigation++;
              _loading = true;
              _document = Uri.tryParse(url);
              _message = null;
            });
          },
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _document = Uri.tryParse(url);
            });
            if (_document case final Uri page when isCampusCardPage(page)) {
              unawaited(_readBalance());
            }
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame != false) {
              _report('学校页面加载失败，请检查网络后重试。', loadFailed: true);
            }
          },
        ),
      );
      if (_controller.platform case final AndroidWebViewController platform) {
        await enableAndroidCashierFrames(platform.webViewIdentifier);
      }
      if (mounted) await _open();
    } catch (_) {
      _report('校园卡页面暂时无法打开。', loadFailed: true);
    }
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final target = Uri.tryParse(request.url);
    if ((target != null && campusCardNavigationAllowed(target)) ||
        (!request.isMainFrame && request.url == 'about:blank')) {
      return NavigationDecision.navigate;
    }
    if (!mounted || !request.isMainFrame) return NavigationDecision.prevent;

    final source = _document;
    if (target != null) {
      final cashier = campusCardCashier(target);
      if (cashier != null && campusCardPaymentAllowedFrom(source, cashier)) {
        if (cashier == CampusCardWallet.wechat &&
            source != null &&
            isCampusCardPage(source)) {
          unawaited(_openWeChatCashier(target, source));
          return NavigationDecision.prevent;
        }
        return NavigationDecision.navigate;
      }
      final link = campusCardWalletLink(target);
      if (link != null && campusCardPaymentAllowedFrom(source, link.wallet)) {
        unawaited(_openWallet(link));
        return NavigationDecision.prevent;
      }
    }
    _report('此页面请从右上角在浏览器打开校园卡后办理。');
    return NavigationDecision.prevent;
  }

  Future<void> _openWeChatCashier(Uri target, Uri source) async {
    try {
      // WeChat H5 validates the merchant referrer. Pass the actual school
      // origin when WebView reloads the cross-origin navigation.
      await _controller.loadRequest(
        target,
        headers: {'Referer': '${source.origin}/'},
      );
    } catch (_) {
      _report('无法打开微信收银台，请从右上角在浏览器打开校园卡。');
    }
  }

  Future<void> _openWallet(CampusCardWalletLink link) async {
    if (_openingWallet || ModalRoute.of(context)?.isCurrent == false) return;
    _openingWallet = true;
    final navigation = _navigation;
    try {
      if (await launchCampusCardWallet(link)) return;
    } catch (_) {
      // Wallet launch errors may include the checkout URI.
    } finally {
      _openingWallet = false;
    }
    if (navigation == _navigation) {
      _report('无法打开${link.wallet.label}。请确认已安装，或从右上角在浏览器打开校园卡。');
    }
  }

  Future<void> _open() async {
    try {
      await _controller.loadRequest(campusCardEntry);
    } catch (_) {
      _report('校园卡页面暂时无法打开。', loadFailed: true);
    }
  }

  void _report(String text, {bool loadFailed = false}) {
    if (!mounted) return;
    setState(() {
      if (loadFailed) _loading = false;
      _message = text;
    });
  }

  Future<void> _readBalance() async {
    final readingPage = _navigation;
    if (_loading || _reading) return;
    _reading = true;
    try {
      for (var attempt = 0; attempt < 5; attempt++) {
        if (!mounted || readingPage != _navigation) return;
        try {
          await widget.repository.save(_controller);
          if (!mounted) return;
          ref.invalidate(campusCardBalanceProvider);
          return;
        } on CampusCardReadFailure catch (error) {
          if (error == CampusCardReadFailure.accountMismatch) {
            if (readingPage == _navigation) {
              _report('请使用当前工作台对应的学校账号查询余额。');
            }
            return;
          }
          if (attempt < 4) {
            await Future<void>.delayed(const Duration(milliseconds: 300));
          }
        }
      }
    } catch (_) {
      // Retain the previous balance if automatic reading fails.
    } finally {
      _reading = false;
      if (mounted) {
        final page = _document;
        if (readingPage != _navigation &&
            page != null &&
            isCampusCardPage(page)) {
          unawaited(_readBalance());
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('校园卡'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新打开校园卡',
            onPressed: _loading ? null : _open,
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: '在浏览器打开',
            onPressed: () =>
                openOfficialPage(context, campusCardEntry.toString()),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_message case final String message)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                child: Text(message, textAlign: TextAlign.center),
              ),
            Expanded(child: _view),
          ],
        ),
      ),
    );
  }
}
