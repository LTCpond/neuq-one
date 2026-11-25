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
  CampusCardRepository(
    this._storage,
    this._subject, {
    this._requestSchoolSignIn,
  });

  final FlutterSecureStorage _storage;
  final String _subject;
  final Future<Uri> Function(Uri login)? _requestSchoolSignIn;
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

  Future<Uri?> schoolSignIn(Uri login) async {
    final request = _requestSchoolSignIn;
    if (_disposed || request == null) return null;
    try {
      final callback = await request(login)
          .timeout(const Duration(seconds: 15));
      return _disposed ? null : callback;
    } catch (_) {
      return null;
    }
  }

  Future<CampusCardBalance> _readOfficialPage() async {
    final controller = WebViewController();
    final result = Completer<CampusCardBalance?>();
    var failure = CampusCardReadFailure.unreadable;
    var navigation = 0;
    var attemptedSchoolSignIn = false;
    var waitingForSchoolSignIn = false;
    void fail(CampusCardReadFailure error) {
      if (result.isCompleted) return;
      failure = error;
      result.complete(null);
    }

    Future<void> readBalance(int currentNavigation) async {
      for (var attempt = 0; attempt < 5; attempt++) {
        if (_disposed ||
            result.isCompleted ||
            currentNavigation != navigation) {
          return;
        }
        try {
          final balance = await save(controller);
          if (!result.isCompleted && currentNavigation == navigation) {
            result.complete(balance);
          }
          return;
        } on CampusCardReadFailure catch (error) {
          if (currentNavigation != navigation) return;
          if (error != CampusCardReadFailure.unreadable) {
            fail(error);
            return;
          }
        } catch (_) {
          if (currentNavigation == navigation) {
            fail(CampusCardReadFailure.unreadable);
          }
          return;
        }
        if (attempt < 4) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
      if (currentNavigation == navigation) {
        fail(CampusCardReadFailure.unreadable);
      }
    }

    Future<void> finishSchoolSignIn(Uri login) async {
      final callback = await schoolSignIn(login);
      if (_disposed || result.isCompleted) return;
      waitingForSchoolSignIn = false;
      try {
        await controller.loadRequest(callback ?? login);
      } catch (_) {
        fail(CampusCardReadFailure.unreadable);
      }
    }

    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (request.isMainFrame &&
              uri != null &&
              !attemptedSchoolSignIn &&
              campusCardCasService(uri) != null) {
            navigation++;
            attemptedSchoolSignIn = true;
            waitingForSchoolSignIn = true;
            unawaited(finishSchoolSignIn(uri));
            return NavigationDecision.prevent;
          }
          if ((uri != null && campusCardNavigationAllowed(uri)) ||
              (!request.isMainFrame && request.url == 'about:blank')) {
            return NavigationDecision.navigate;
          }
          if (request.isMainFrame) fail(CampusCardReadFailure.unreadable);
          return NavigationDecision.prevent;
        },
        onPageStarted: (_) => navigation++,
        onPageFinished: (url) {
          if (waitingForSchoolSignIn) return;
          final uri = Uri.tryParse(url);
          if (uri != null && isCampusCardPage(uri)) {
            unawaited(readBalance(navigation));
          } else if (uri?.host == schoolIdentityHost) {
            fail(CampusCardReadFailure.signInRequired);
          }
        },
        onWebResourceError: (error) {
          if (!waitingForSchoolSignIn && error.isForMainFrame != false) {
            fail(CampusCardReadFailure.unreadable);
          }
        },
      ),
    );
    if (_disposed) throw CampusCardReadFailure.unreadable;
    await controller.loadRequest(campusCardEntry);
    final balance = await result.future.timeout(
      const Duration(seconds: 25),
      onTimeout: () {
        fail(CampusCardReadFailure.unreadable);
        return null;
      },
    );
    if (balance == null) throw failure;
    return balance;
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
  final client = ref.watch(neuqClientProvider);
  final repository = CampusCardRepository(
    ref.watch(schoolTicketStorageProvider),
    subject,
    requestSchoolSignIn: (login) => client.campusCardSignIn(subject, login),
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
