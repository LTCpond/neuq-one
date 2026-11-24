import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuq_one/features/services/data/campus_card_camera.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const camera = CampusCardCamera();
  const channel = MethodChannel('org.neuqone.neuq_one/campus_card_camera');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'camera access follows the system decision for the requested webview',
    () async {
      for (final allowed in [true, false]) {
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'requestCameraPermission');
          expect(call.arguments, 17);
          return allowed;
        });
        expect(await camera.request(androidWebViewIdentifier: 17), allowed);
      }
    },
  );

  test(
    'camera access fails closed when native permission support is unavailable',
    () async {
      expect(await camera.request(), isFalse);
      expect(await camera.request(androidWebViewIdentifier: 17), isFalse);
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'unavailable');
      });
      expect(await camera.request(androidWebViewIdentifier: 17), isFalse);
    },
  );

  test('iOS leaves the system camera prompt to WebKit', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => fail('Android channel called on iOS'),
    );
    expect(await camera.request(), isTrue);
  });
}
