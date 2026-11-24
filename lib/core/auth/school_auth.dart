import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'neuq_login_protocol.dart';

enum SchoolConnection { unavailable, disconnected, connected }

class SchoolSession {
  const SchoolSession({required this.subject, this.admissionYear});

  /// Stable pseudonymous identifier for a verified student account.
  final String subject;

  /// Applicable cohort from the school's enrollment record, including reclassification.
  final int? admissionYear;
}

abstract interface class SchoolAuthRepository {
  bool get available;

  /// Restores the device identity established by a previous school login.
  Future<SchoolSession?> restoreSession();

  Future<SchoolSession?> signIn({SchoolLoginPresenter? openLogin});

  /// Clears the stored local session before attempting remote sign-out.
  Future<void> disconnect();
}

typedef SchoolLoginPresenter = Future<SchoolSession?> Function();

class UnavailableSchoolAuthRepository implements SchoolAuthRepository {
  const UnavailableSchoolAuthRepository();

  @override
  bool get available => false;
  @override
  Future<SchoolSession?> restoreSession() async => null;
  @override
  Future<SchoolSession?> signIn({SchoolLoginPresenter? openLogin}) async =>
      null;
  @override
  Future<void> disconnect() async {}
}

class NeuqWebAuthRepository implements SchoolAuthRepository {
  NeuqWebAuthRepository(this._storage);

  static const _identityKey = 'verifiedNeuqStudent';
  final FlutterSecureStorage _storage;

  @override
  bool get available =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<SchoolSession?> restoreSession() async {
    final subject = await _storage.read(key: _identityKey);
    if (subject == null || !isStoredSchoolSubject(subject)) return null;
    return SchoolSession(subject: subject);
  }

  @override
  Future<SchoolSession?> signIn({SchoolLoginPresenter? openLogin}) async {
    if (openLogin == null || !available) return null;
    await WebViewCookieManager().clearCookies();
    final session = await openLogin();
    if (session == null || !isStoredSchoolSubject(session.subject)) return null;
    await _storage.write(key: _identityKey, value: session.subject);
    return session;
  }

  @override
  Future<void> disconnect() async {
    try {
      await _storage.delete(key: _identityKey);
    } finally {
      if (available) await WebViewCookieManager().clearCookies();
    }
  }
}

final schoolAuthRepositoryProvider = Provider<SchoolAuthRepository>(
  (ref) => NeuqWebAuthRepository(ref.watch(schoolTicketStorageProvider)),
);

final schoolSessionProvider =
    AsyncNotifierProvider<SchoolSessionController, SchoolSession?>(
      SchoolSessionController.new,
      retry: (_, _) => null,
    );

class SchoolSessionController extends AsyncNotifier<SchoolSession?> {
  @override
  Future<SchoolSession?> build() {
    final repository = ref.watch(schoolAuthRepositoryProvider);
    return repository.available ? repository.restoreSession() : Future.value();
  }

  Future<void> signIn({SchoolLoginPresenter? openLogin}) async {
    if (state.isLoading) return;
    final repository = ref.read(schoolAuthRepositoryProvider);
    if (!repository.available) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => repository.signIn(openLogin: openLogin),
    );
  }

  Future<void> disconnect() async {
    final repository = ref.read(schoolAuthRepositoryProvider);
    state = const AsyncLoading();
    try {
      await repository.disconnect();
    } finally {
      state = const AsyncData(null);
    }
  }
}

final schoolConnectionProvider = FutureProvider<SchoolConnection>((ref) async {
  if (!ref.watch(schoolAuthRepositoryProvider).available) {
    return SchoolConnection.unavailable;
  }
  final session = await ref.watch(schoolSessionProvider.future);
  return session == null
      ? SchoolConnection.disconnected
      : SchoolConnection.connected;
});

final schoolTicketStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
);
