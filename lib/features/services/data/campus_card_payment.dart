import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'campus_card_protocol.dart';

enum CampusCardWallet {
  wechat('微信', 'com.tencent.mm'),
  alipay('支付宝', 'com.eg.android.AlipayGphone');

  const CampusCardWallet(this.label, this.androidPackage);

  final String label;
  final String androidPackage;
}

CampusCardWallet? campusCardCashier(Uri uri) {
  if (uri.scheme != 'https' || uri.port != 443 || uri.userInfo.isNotEmpty) {
    return null;
  }
  return switch ((uri.host, uri.path)) {
    ('wx.tenpay.com', '/cgi-bin/mmpayweb-bin/checkmweb') =>
      CampusCardWallet.wechat,
    ('mclient.alipay.com', _) ||
    ('openapi.alipay.com', '/gateway.do') ||
    ('render.alipay.com', '/p/s/i/') => CampusCardWallet.alipay,
    _ => null,
  };
}

bool campusCardPaymentAllowedFrom(Uri? source, CampusCardWallet wallet) =>
    source != null &&
    (isCampusCardPage(source) || campusCardCashier(source) == wallet);

typedef CampusCardWalletLink = ({CampusCardWallet wallet, Uri uri});

CampusCardWalletLink? campusCardWalletLink(Uri target) {
  if (target.scheme != 'intent') return _walletLink(target);

  final fields = target.fragment.split(';');
  if (fields.first != 'Intent' || fields.last != 'end') return null;
  final schemes = fields.where((field) => field.startsWith('scheme=')).toList();
  if (schemes.length != 1) return null;
  final scheme = schemes.single.substring(7);
  if (scheme != 'weixin' && scheme != 'alipays') return null;

  // Keep the checkout URI and discard Android intent extras, fallback URLs
  // and components. The app constructs a fresh ACTION_VIEW for the wallet.
  final uri = target.removeFragment().replace(scheme: scheme);
  final link = _walletLink(uri);
  if (link == null) return null;
  final packages = fields
      .where((field) => field.startsWith('package='))
      .toList();
  if (packages.length > 1 ||
      (packages.isNotEmpty &&
          packages.single != 'package=${link.wallet.androidPackage}')) {
    return null;
  }
  return link;
}

CampusCardWalletLink? _walletLink(Uri uri) {
  if (uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.hasFragment ||
      uri.query.isEmpty) {
    return null;
  }
  final wallet = switch ((uri.scheme, uri.host, uri.path)) {
    ('weixin', 'wap', '/pay') => CampusCardWallet.wechat,
    ('alipays', 'platformapi', '/startapp' || '/startApp') =>
      CampusCardWallet.alipay,
    _ => null,
  };
  return wallet == null ? null : (wallet: wallet, uri: uri);
}

const _channel = MethodChannel('org.neuqone.neuq_one/campus_card_payment');

Future<bool> launchCampusCardWallet(CampusCardWalletLink link) async {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return await _channel.invokeMethod<bool>(
          'openWallet',
          link.uri.toString(),
        ) ??
        false;
  }
  return launchUrl(link.uri, mode: LaunchMode.externalApplication);
}

Future<void> enableAndroidCashierFrames(int webViewIdentifier) =>
    _channel.invokeMethod<void>('watchCashierFrames', webViewIdentifier);

Future<bool> openCampusCardWeChat() async {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return await _channel.invokeMethod<bool>('openWeChat') ?? false;
  }
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return launchUrl(
      Uri.parse('weixin://'),
      mode: LaunchMode.externalApplication,
    );
  }
  return false;
}
