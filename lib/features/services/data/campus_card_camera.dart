import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final campusCardCameraProvider = Provider((ref) => const CampusCardCamera());

class CampusCardCamera {
  const CampusCardCamera();

  static const _channel = MethodChannel(
    'org.neuqone.neuq_one/campus_card_camera',
  );

  Future<bool> request({int? androidWebViewIdentifier}) async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // WebKit presents the system camera prompt after the web request is granted.
      return true;
    }
    if (defaultTargetPlatform != TargetPlatform.android ||
        androidWebViewIdentifier == null) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>(
            'requestCameraPermission',
            androidWebViewIdentifier,
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
