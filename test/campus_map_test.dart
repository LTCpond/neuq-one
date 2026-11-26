import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:neuq_one/core/network/public_data_client.dart';
import 'package:neuq_one/core/theme/app_theme.dart';
import 'package:neuq_one/features/services/data/campus_map.dart';
import 'package:neuq_one/features/services/presentation/campus_map_page.dart';

final _firstMap = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAACAAAAAQCAIAAAD4YuoOAAAAIElEQVR42mNUiXzAQEvAxEBjMGrBqAWjFoxaMGoBNQAAp+IBfTCxk8MAAAAASUVORK5CYII=',
);
final _updatedMap = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAACAAAAAQCAIAAAD4YuoOAAAAIElEQVR42mO89jmHgZaAiYHGYNSCUQtGLRi1YNQCagAAxSMCVWKILU8AAAAASUVORK5CYII=',
);
final _legacyMap = base64Decode(
  'UklGRh4AAABXRUJQVlA4TBEAAAAvH8ADAAfQrJIUvP+BiOh/AAA=',
);
const _modified = 'Wed, 25 Nov 2026 10:00:00 GMT';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('neuq-map-test-');
  });
  tearDown(() => directory.delete(recursive: true));

  CampusMapRepository repository(
    Future<http.Response> Function(http.Request) respond,
  ) {
    final client = MockClient(respond);
    addTearDown(client.close);
    return CampusMapRepository(PublicDataClient(client), () async => directory);
  }

  test(
    'persists PNG and validators and reuses the previous map on 304',
    () async {
      final disk = repository((request) async {
        expect(
          request.url,
          publicAssetsRoot.resolve('/assets/maps/campus-map.png'),
        );
        expect(request.headers['accept'], 'image/png');
        expect(request.headers['cache-control'], 'no-cache');
        expect(request.headers.containsKey('if-none-match'), isFalse);
        return _ok(_firstMap, '"first"');
      });
      expect(await disk.readCached(), isNull);
      expect((await disk.refresh(null)).bytes, _firstMap);

      final reopened = repository((request) async {
        expect(request.headers['if-none-match'], '"first"');
        expect(request.headers['if-modified-since'], _modified);
        return http.Response('', 304);
      });
      final stored = (await reopened.readCached())!;
      expect(stored.bytes, _firstMap);
      expect(await reopened.refresh(stored), same(stored));
    },
  );

  test(
    'keeps the old-site PNG offline and revalidates from the new origin',
    () async {
      var online = false;
      final disk = repository((request) async {
        expect(request.url.origin, publicAssetsRoot.origin);
        expect(request.headers['if-none-match'], isNull);
        expect(request.headers['if-modified-since'], isNull);
        if (!online) throw const SocketException('offline');
        return _ok(_updatedMap, '"new"');
      });
      final cache = File.fromUri(
        directory.uri.resolve('neuq_one_campus_map.cache'),
      );
      await cache.writeAsBytes([
        ...utf8.encode(
          '${jsonEncode({'etag': '"old"', 'lastModified': _modified})}\n',
        ),
        ..._firstMap,
      ]);
      expect((await disk.load().single).bytes, _firstMap);
      online = true;
      expect(await disk.load().map((map) => map.bytes).toList(), [
        _firstMap,
        _updatedMap,
      ]);
      expect((await disk.readCached())!.etag, '"new"');
    },
  );

  test(
    'rejects invalid maps and replaces the image and validators together',
    () async {
      final invalidPng = Uint8List.fromList(_updatedMap)..fillRange(16, 24, 0);
      var body = _firstMap;
      var etag = '"first"';
      final disk = repository((_) async => _ok(body, etag));
      final initial = await disk.refresh(null);
      for (final invalid in [
        Uint8List.fromList(utf8.encode('<html>')),
        _legacyMap,
        Uint8List.sublistView(_updatedMap, 0, _updatedMap.length - 12),
        invalidPng,
      ]) {
        body = invalid;
        etag = '"bad"';
        await expectLater(disk.refresh(initial), throwsA(isA<Exception>()));
        final stored = (await disk.readCached())!;
        expect(stored.bytes, _firstMap);
        expect(stored.etag, '"first"');
      }
      body = _updatedMap;
      etag = '"new"';
      await disk.refresh(initial);
      final stored = (await disk.readCached())!;
      expect(stored.bytes, _updatedMap);
      expect(stored.etag, '"new"');
      expect(await directory.list().length, 1);
    },
  );

  test(
    'keeps a legacy map offline and fetches PNG without old validators',
    () async {
      var online = true;
      final disk = repository((request) async {
        expect(request.headers.containsKey('if-none-match'), isFalse);
        expect(request.headers.containsKey('if-modified-since'), isFalse);
        if (!online) throw const SocketException('offline');
        return _ok(_firstMap, '"png"');
      });
      await disk.refresh(null);
      final file = (await directory.list().single) as File;
      await file.writeAsBytes([
        ...utf8.encode(
          '${jsonEncode({'etag': '"webp"', 'lastModified': _modified})}\n',
        ),
        ..._legacyMap,
      ]);

      online = false;
      expect((await disk.load().single).bytes, _legacyMap);
      online = true;
      expect(await disk.load().map((map) => map.bytes).toList(), [
        _legacyMap,
        _firstMap,
      ]);
      expect((await disk.readCached())!.etag, '"png"');
    },
  );

  test('shows the disk cache while checking for updates and stays readable offline', () async {
    final initial = repository((_) async => _ok(_firstMap, '"first"'));
    await initial.refresh(null);
    final pending = Completer<http.Response>();
    final requested = Completer<void>();
    final offline = repository((request) {
      expect(request.headers['if-none-match'], '"first"');
      requested.complete();
      return pending.future;
    });
    final container = ProviderContainer.test(
      overrides: [campusMapRepositoryProvider.overrideWithValue(offline)],
    );
    final state = container.listen(campusMapProvider, (_, _) {});
    final cached = await container.read(campusMapProvider.future);
    expect(cached.bytes, _firstMap);
    await requested.future;
    expect(pending.isCompleted, isFalse);
    final refresh = offline.refresh(cached);
    pending.completeError(const SocketException('offline'));
    await expectLater(refresh, throwsA(isA<SocketException>()));
    expect(state.read().requireValue, same(cached));
    expect((await offline.readCached())!.bytes, _firstMap);
  });

  test(
    'discards an unreadable cache and requests the complete resource',
    () async {
      final disk = repository((request) async {
        expect(request.headers.containsKey('if-none-match'), isFalse);
        return _ok(_firstMap, '"first"');
      });
      await disk.refresh(null);
      final file = (await directory.list().single) as File;
      await file.writeAsString('{"etag":"broken"}\ninvalid');
      expect(await disk.readCached(), isNull);
      expect((await disk.refresh(null)).bytes, _firstMap);
    },
  );

  testWidgets('shows initial loading and recovers through retry', (
    tester,
  ) async {
    final first = Completer<CampusMap>();
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          campusMapProvider.overrideWith(
            (ref) => ++attempts == 1
                ? first.future.asStream()
                : Stream.value(CampusMap(_firstMap)),
          ),
        ],
        child: const MaterialApp(home: CampusMapPage()),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    first.completeError(const SocketException('offline'));
    await tester.pumpAndSettle();
    expect(find.text('校园地图加载失败'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('校园地图加载失败'), findsNothing);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(attempts, 2);
  });

  testWidgets('fits the map, supports gestures and restores system bars', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 780);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    const channel = MethodChannel('org.neuqone.neuq_one/campus_map');
    final fullscreens = <Object?>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'setFullscreen');
      fullscreens.add(call.arguments);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          campusMapProvider.overrideWith(
            (ref) => Stream.value(CampusMap(_firstMap)),
          ),
        ],
        child: MaterialApp(
          theme: appTheme(Brightness.dark),
          home: const CampusMapPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final viewer = find.byType(InteractiveViewer);
    TransformationController controller() =>
        tester.widget<InteractiveViewer>(viewer).transformationController!;
    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
    expect(controller().value.isIdentity(), isTrue);

    final center = tester.getCenter(viewer);
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(controller().value.getMaxScaleOnAxis(), 2);
    final zoomed = controller().value.clone();
    await tester.dragFrom(center, const Offset(50, 40));
    await tester.pumpAndSettle();
    expect(controller().value.getTranslation(), isNot(zoomed.getTranslation()));
    await tester.tap(find.byTooltip('恢复初始视角'));
    await tester.pumpAndSettle();
    expect(controller().value.isIdentity(), isTrue);

    final left = await tester.startGesture(center - const Offset(30, 0));
    final right = await tester.startGesture(center + const Offset(30, 0));
    await left.moveBy(const Offset(-50, 0));
    await right.moveBy(const Offset(50, 0));
    await left.up();
    await right.up();
    await tester.pumpAndSettle();
    expect(controller().value.getMaxScaleOnAxis(), greaterThan(1));
    tester.view.physicalSize = const Size(780, 420);
    await tester.pumpAndSettle();
    expect(controller().value.isIdentity(), isTrue);
    expect(tester.getSize(viewer).width, 780);

    await tester.tap(find.byTooltip('全屏查看'));
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
    expect(find.byTooltip('退出全屏'), findsOneWidget);
    expect(tester.getSize(viewer).height, 420);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
    expect(fullscreens, [true, false]);

    await tester.tap(find.byTooltip('全屏查看'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(fullscreens, [true, false, true, false]);
  });
}

http.Response _ok(Uint8List body, String etag) => http.Response.bytes(
  body,
  200,
  headers: {
    'content-type': 'image/png',
    'etag': etag,
    'last-modified': _modified,
  },
);
