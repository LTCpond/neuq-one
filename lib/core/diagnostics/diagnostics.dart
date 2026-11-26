import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

enum DiagnosticSeverity { debug, info, warn, error }

enum DiagnosticModule {
  schoolAuth,
  academics,
  reminders,
  publicData,
  updates,
  cache,
  campusCard,
}

enum DiagnosticStage {
  restore,
  signIn,
  renew,
  request,
  decode,
  sync,
  initialize,
  permission,
  schedule,
  cancel,
  show,
  read,
  write,
  clear,
  check,
}

enum DiagnosticCode {
  completed,
  network,
  timeout,
  invalidData,
  permissionDenied,
  sessionExpired,
  rejected,
  storage,
  platform,
  missingResource,
  unavailable,
  unexpected,
  automaticCheck,
  manualCheck,
  checkInterval,
  retryBackoff,
  stableChannel,
  betaChannel,
  noPublishedRelease,
  upToDate,
  updateAvailable,
  promptAlreadyShown,
  promptDeferred,
  promptShown,
}

typedef DiagnosticEntry = ({
  DateTime time,
  DiagnosticSeverity level,
  DiagnosticModule module,
  DiagnosticStage stage,
  DiagnosticCode code,
  String? exceptionType,
});

final diagnostics = Diagnostics();

/// Stores only enumerated context and the exception type. Messages, stack
/// traces, request details and arbitrary metadata never enter the buffer.
class Diagnostics {
  static const capacity = 150;
  final _entries = Queue<DiagnosticEntry>();

  List<DiagnosticEntry> get entries => List.unmodifiable(_entries);

  void record(
    DiagnosticModule module,
    DiagnosticStage stage, {
    DiagnosticSeverity level = DiagnosticSeverity.warn,
    DiagnosticCode? code,
    Object? error,
  }) {
    if (_entries.length == capacity) _entries.removeFirst();
    _entries.add((
      time: DateTime.now().toUtc(),
      level: level,
      module: module,
      stage: stage,
      code: code ?? _classify(error),
      exceptionType: error?.runtimeType.toString(),
    ));
  }

  void clear() => _entries.clear();

  static DiagnosticCode _classify(Object? error) => switch (error) {
    TimeoutException() => DiagnosticCode.timeout,
    FormatException() || TypeError() => DiagnosticCode.invalidData,
    FileSystemException() => DiagnosticCode.storage,
    SocketException() ||
    HandshakeException() ||
    HttpException() ||
    http.ClientException() => DiagnosticCode.network,
    PlatformException(code: 'invalid_icon') => DiagnosticCode.missingResource,
    PlatformException(code: 'exact_alarms_not_permitted') =>
      DiagnosticCode.permissionDenied,
    PlatformException() || MissingPluginException() => DiagnosticCode.platform,
    null => DiagnosticCode.completed,
    _ => DiagnosticCode.unexpected,
  };
}
