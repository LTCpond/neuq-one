import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/auth/neuq_login_protocol.dart';
import '../../../core/auth/school_auth.dart';
import 'campus_card_protocol.dart';

typedef CampusCardBalance = ({int cents, DateTime readAt});

enum CampusCardRefreshStatus { updated, signInRequired, unavailable }

class CampusCardRepository {
  CampusCardRepository(this._storage, this._subject);

  final FlutterSecureStorage _storage;
  final String _subject;
  Future<CampusCardBalance>? _refreshing;
  bool _disposed = false;
  String get _key => 'campusCardBalance:$_subject';

  Future<CampusCardBalance?> load() async {
    final stored = await _storage.read(key: _key);
    if (stored == null) return null;
    try {
      final data = jsonDecode(stored);
      if (data is! Map || data['cents'] is! int || data['readAt'] is! String) {
        return null;
      }
      final cents = data['cents'] as int;
      final date = DateTime.tryParse(data['readAt'] as String);
      if (date == null || !validCampusCardCents(cents)) return null;
      return (cents: cents, readAt: date.toUtc());
    } on FormatException {
      return null;
    }
  }

  Future<CampusCardBalance> save(WebViewController controller) async {
    final before = Uri.tryParse(await controller.currentUrl() ?? '');
    if (before == null || !isCampusCardPage(before)) {
      throw CampusCardReadFailure.unreadable;
    }
    final evidence = await controller.runJavaScriptReturningResult(
      campusCardBalanceProbe,
    );
    final after = Uri.tryParse(await controller.currentUrl() ?? '');
    if (_disposed || after != before) throw CampusCardReadFailure.unreadable;
    final cents = readCampusCardBalance(before, evidence, _subject);
    final now = DateTime.now().toUtc();
    await _storage.write(
      key: _key,
      value: jsonEncode({'cents': cents, 'readAt': now.toIso8601String()}),
    );
    return (cents: cents, readAt: now);
  }

  Future<CampusCardBalance> refresh() =>
      _refreshing ??= _readOfficialPage().whenComplete(() {
        _refreshing = null;
      });

  Future<CampusCardBalance> _readOfficialPage() async {
    final controller = WebViewController();
    final loaded = Completer<CampusCardReadFailure?>();
    void complete(CampusCardReadFailure? failure) {
      if (!loaded.isCompleted) loaded.complete(failure);
    }

    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if ((uri != null && campusCardNavigationAllowed(uri)) ||
              (!request.isMainFrame && request.url == 'about:blank')) {
            return NavigationDecision.navigate;
          }
          if (request.isMainFrame) complete(CampusCardReadFailure.unreadable);
          return NavigationDecision.prevent;
        },
        onPageFinished: (url) {
          final uri = Uri.tryParse(url);
          if (uri != null && isCampusCardPage(uri)) {
            complete(null);
          } else if (uri?.host == schoolIdentityHost) {
            complete(CampusCardReadFailure.signInRequired);
          }
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame != false) {
            complete(CampusCardReadFailure.unreadable);
          }
        },
      ),
    );
    if (_disposed) throw CampusCardReadFailure.unreadable;
    await controller.loadRequest(campusCardEntry);
    final failure = await loaded.future.timeout(const Duration(seconds: 10));
    if (failure != null) throw failure;
    for (var attempt = 0; attempt < 5 && !_disposed; attempt++) {
      try {
        return await save(controller);
      } on CampusCardReadFailure catch (error) {
        if (error != CampusCardReadFailure.unreadable) rethrow;
        if (attempt < 4) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
    }
    throw CampusCardReadFailure.unreadable;
  }

  void dispose() => _disposed = true;
}

final campusCardRepositoryProvider = Provider<CampusCardRepository?>((ref) {
  final available = ref.watch(schoolAuthRepositoryProvider).available;
  final subject = ref.watch(
    schoolSessionProvider.select((session) => session.asData?.value?.subject),
  );
  if (!available || subject == null || !isStoredSchoolSubject(subject)) {
    return null;
  }
  final repository = CampusCardRepository(
    ref.watch(schoolTicketStorageProvider),
    subject,
  );
  ref.onDispose(repository.dispose);
  return repository;
});

final campusCardBalanceProvider =
    FutureProvider.autoDispose<CampusCardBalance?>(
      (ref) async => ref.watch(campusCardRepositoryProvider)?.load(),
      retry: (_, _) => null,
    );

final campusCardRefreshProvider =
    FutureProvider.autoDispose<CampusCardRefreshStatus?>((ref) async {
      final repository = ref.watch(campusCardRepositoryProvider);
      if (repository == null) return null;
      try {
        await repository.refresh();
        if (ref.mounted) ref.invalidate(campusCardBalanceProvider);
        return CampusCardRefreshStatus.updated;
      } on CampusCardReadFailure catch (error) {
        return error == CampusCardReadFailure.unreadable
            ? CampusCardRefreshStatus.unavailable
            : CampusCardRefreshStatus.signInRequired;
      } catch (_) {
        return CampusCardRefreshStatus.unavailable;
      }
    }, retry: (_, _) => null);

String campusCardMoney(int cents) {
  final amount = cents.abs();
  final fraction = (amount % 100).toString().padLeft(2, '0');
  return '${cents < 0 ? '−' : ''}¥${amount ~/ 100}.$fraction';
}
