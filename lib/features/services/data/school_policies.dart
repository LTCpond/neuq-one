import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/network/public_data_client.dart';
import '../../../core/diagnostics/diagnostics.dart';
import '../../../core/storage/cache_files.dart';
import '../../../core/storage/picker_cache.dart';
import '../domain/school_policy.dart';

final schoolPolicyRepositoryProvider = Provider<SchoolPolicyRepository>(
  (ref) => SchoolPolicyRepository(
    ref.watch(publicDataClientProvider),
    getApplicationSupportDirectory,
  ),
);

final schoolPoliciesProvider = StreamProvider.autoDispose<List<SchoolPolicy>>(
  (ref) => ref.watch(schoolPolicyRepositoryProvider).loadCatalog(),
  retry: (_, _) => null,
);

final schoolPolicyPdfProvider = FutureProvider.autoDispose
    .family<Uint8List, SchoolPolicy>(
      (ref, policy) =>
          ref.watch(schoolPolicyRepositoryProvider).loadPdf(policy),
      retry: (_, _) => null,
    );

final saveSchoolPolicyProvider = Provider<SchoolPolicySaver>(
  (ref) => (policy, bytes) async {
    final filename = policy.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '');
    return await pickerCache.run(
          () => FilePicker.saveFile(
            dialogTitle: '保存学校政策',
            fileName: '$filename.pdf',
            mimeType: 'application/pdf',
            bytes: bytes,
          ),
        ) !=
        null;
  },
);

typedef SchoolPolicySaver = Future<bool> Function(
  SchoolPolicy policy,
  Uint8List bytes,
);

class SchoolPolicyRepository {
  SchoolPolicyRepository(this._client, this._directory);

  static const _root = '/assets/policies';
  static const _index = 'index.json';
  static const _maxIndexBytes = 128 * 1024;
  static const _maxPdfBytes = 25 * 1024 * 1024;
  static final _idPattern = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');
  static final _digestPattern = RegExp(r'^[a-f0-9]{64}$');

  final PublicDataClient _client;
  final Future<Directory> Function() _directory;
  final _writes = CacheWrites();

  Future<int> cacheBytes() async => cacheFileBytes(await _cacheDirectory());

  Future<void> clearCache() => _writes.clear(() async {
    await deleteCacheEntity(await _cacheDirectory());
  });

  Stream<List<SchoolPolicy>> loadCatalog() async* {
    final version = _writes.version;
    final cached = await _read(_index, _maxIndexBytes);
    if (!_writes.current(version)) return;
    List<SchoolPolicy>? catalog;
    if (cached != null) {
      try {
        catalog = _parseCatalog(cached);
      } on FormatException catch (error) {
        diagnostics.record(
          DiagnosticModule.cache,
          DiagnosticStage.decode,
          error: error,
        );
      }
    }
    if (catalog != null) yield catalog;

    try {
      if (!_writes.current(version)) return;
      final response = await _client.getBytes(
        '$_root/$_index',
        source: PublicDataSource.assets,
        accept: 'application/json',
        revalidate: true,
        maxBytes: _maxIndexBytes,
      );
      final bytes = response.body;
      if (bytes == null) throw const FormatException('缺少学校政策目录');
      final updated = _parseCatalog(bytes);
      if (catalog == null || !listEquals(bytes, cached)) {
        await _writes.write(version, () => _store(_index, bytes));
        if (_writes.current(version)) yield updated;
      }
    } catch (error) {
      diagnostics.record(
        DiagnosticModule.publicData,
        DiagnosticStage.request,
        error: error,
      );
      if (catalog == null) rethrow;
    }
  }

  Future<Uint8List> loadPdf(SchoolPolicy policy) async {
    final version = _writes.version;
    if (version == null) throw const FormatException('正在清理学校政策缓存');
    final name = '${policy.id}.pdf';
    final cached = await _read(name, _maxPdfBytes);
    if (cached != null && _validPdf(cached, policy.sha256)) return cached;

    final response = await _client.getBytes(
      '$_root/$name',
      source: PublicDataSource.assets,
      accept: 'application/pdf',
      revalidate: true,
      maxBytes: _maxPdfBytes,
      timeout: const Duration(seconds: 30),
    );
    final bytes = response.body;
    if (bytes == null || !_validPdf(bytes, policy.sha256)) {
      throw const FormatException('学校政策文件校验失败');
    }
    await _writes.write(version, () => _store(name, bytes));
    return bytes;
  }

  static bool _validPdf(Uint8List bytes, String digest) =>
      bytes.length >= 5 &&
      String.fromCharCodes(bytes, 0, 5) == '%PDF-' &&
      sha256.convert(bytes).toString() == digest;

  static List<SchoolPolicy> _parseCatalog(Uint8List bytes) {
    final json = jsonDecode(utf8.decode(bytes));
    if (json case {'version': 1, 'policies': final List<dynamic> rows}) {
      final policies = <SchoolPolicy>[];
      final ids = <String>{};
      for (final row in rows) {
        if (row
            case {
              'id': final String id,
              'title': final String title,
              'category': final String category,
              'sha256': final String digest,
            }
            when _idPattern.hasMatch(id) &&
                id.length <= 64 &&
                title.trim().isNotEmpty &&
                category.trim().isNotEmpty &&
                _digestPattern.hasMatch(digest) &&
                ids.add(id)) {
          policies.add(
            SchoolPolicy(
              id: id,
              title: title,
              category: category,
              sha256: digest,
            ),
          );
        } else {
          throw const FormatException('学校政策条目格式错误');
        }
      }
      return List.unmodifiable(policies);
    }
    throw const FormatException('学校政策目录格式错误');
  }

  Future<Directory> _cacheDirectory() async =>
      Directory.fromUri((await _directory()).uri.resolve('school-policies/'));

  Future<Uint8List?> _read(String name, int maxBytes) async {
    try {
      final file = File.fromUri((await _cacheDirectory()).uri.resolve(name));
      if (!await file.exists()) return null;
      if (await file.length() <= maxBytes) return await file.readAsBytes();
    } catch (error) {
      diagnostics.record(
        DiagnosticModule.cache,
        DiagnosticStage.read,
        error: error,
      );
    }
    return null;
  }

  Future<void> _store(String name, Uint8List bytes) async {
    try {
      final directory = await (await _cacheDirectory()).create(recursive: true);
      final staging = await directory.createTemp('policy-');
      final temporary = File.fromUri(staging.uri.resolve(name));
      try {
        await temporary.writeAsBytes(bytes, flush: true);
        await temporary.rename(File.fromUri(directory.uri.resolve(name)).path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
        await staging.delete();
      }
    } catch (error) {
      diagnostics.record(
        DiagnosticModule.cache,
        DiagnosticStage.write,
        error: error,
      );
    }
  }
}
