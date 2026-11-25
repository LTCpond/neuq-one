import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/network/public_data_client.dart';

final campusMapRepositoryProvider = Provider<CampusMapRepository>(
  (ref) => CampusMapRepository(
    ref.watch(publicDataClientProvider),
    getApplicationSupportDirectory,
  ),
);

final campusMapProvider = StreamProvider.autoDispose<CampusMap>(
  (ref) => ref.watch(campusMapRepositoryProvider).load(),
  retry: (_, _) => null,
);

class CampusMap {
  const CampusMap(this.bytes, {this.etag, this.lastModified});

  final Uint8List bytes;
  final String? etag;
  final String? lastModified;
}

class CampusMapRepository {
  CampusMapRepository(this._client, this._directory);

  static const _path = '/assets/maps/campus-map.png';
  static const _fileName = 'neuq_one_campus_map.cache';
  static const _maxBytes = 25 * 1024 * 1024;
  static const _maxHeaderBytes = 8 * 1024;
  final PublicDataClient _client;
  final Future<Directory> Function() _directory;
  Future<CampusMap>? _inFlight;

  Stream<CampusMap> load() async* {
    final cached = await readCached();
    if (cached != null) yield cached;
    try {
      final updated = await refresh(cached);
      if (!identical(updated, cached)) yield updated;
    } catch (_) {
      if (cached == null) rethrow;
    }
  }

  Future<CampusMap?> readCached() async {
    try {
      final file = File.fromUri((await _directory()).uri.resolve(_fileName));
      if (await file.length() > _maxBytes + _maxHeaderBytes) return null;
      final entry = await file.readAsBytes();
      final separator = entry.indexOf(0x0a);
      if (separator < 0 || separator >= _maxHeaderBytes) return null;
      final header = jsonDecode(
        utf8.decode(entry.sublist(0, separator)),
      ) as Map<String, dynamic>;
      final bytes = Uint8List.sublistView(entry, separator + 1);
      final isPng = _isPng(bytes);
      if (!isPng && !_isLegacyWebP(bytes)) return null;
      await _validateImage(bytes);
      // Validators for the old WebP URL do not apply to the PNG resource.
      return CampusMap(
        bytes,
        etag: isPng ? header['etag'] as String? : null,
        lastModified: isPng ? header['lastModified'] as String? : null,
      );
    } catch (_) {
      // An unreadable cache falls back to an unconditional download.
      return null;
    }
  }

  Future<CampusMap> refresh(CampusMap? cached) =>
      _inFlight ??= _refresh(cached).whenComplete(() => _inFlight = null);

  Future<CampusMap> _refresh(CampusMap? cached) async {
    final response = await _client.getBytes(
      _path,
      accept: 'image/png',
      etag: cached?.etag,
      lastModified: cached?.lastModified,
      revalidate: true,
      timeout: const Duration(seconds: 30),
      maxBytes: _maxBytes,
    );
    final bytes = response.body;
    if (bytes == null) {
      return cached ?? (throw const FormatException('校园地图缓存缺失'));
    }
    if (!_isPng(bytes)) {
      throw const FormatException('校园地图不是有效的 PNG 文件');
    }
    await _validateImage(bytes);
    final map = CampusMap(
      bytes,
      etag: response.headers['etag'],
      lastModified: response.headers['last-modified'],
    );
    try {
      await _write(map);
    } catch (_) {
      // A disk failure still allows the validated image to be displayed.
    }
    return map;
  }

  Future<void> _write(CampusMap map) async {
    final metadata = utf8.encode(
      '${jsonEncode({'etag': map.etag, 'lastModified': map.lastModified})}\n',
    );
    if (metadata.length > _maxHeaderBytes) return;
    final directory = await _directory();
    await directory.create(recursive: true);
    // Store the validators together with the image and replace them in one rename.
    final staging = await directory.createTemp('neuq_one_campus_map-');
    try {
      final file = File.fromUri(staging.uri.resolve(_fileName));
      final output = await file.open(mode: FileMode.write);
      try {
        await output.writeFrom(metadata);
        await output.writeFrom(map.bytes);
        await output.flush();
      } finally {
        await output.close();
      }
      await file.rename(File.fromUri(directory.uri.resolve(_fileName)).path);
    } finally {
      await staging.delete(recursive: true);
    }
  }

  static bool _isPng(Uint8List bytes) {
    if (bytes.length < 20) return false;
    final data = ByteData.sublistView(bytes);
    // Check the PNG signature and complete IEND chunk before decoding.
    return data.getUint32(0) == 0x89504E47 &&
        data.getUint32(4) == 0x0D0A1A0A &&
        data.getUint32(bytes.length - 12) == 0 &&
        data.getUint32(bytes.length - 8) == 0x49454E44 &&
        data.getUint32(bytes.length - 4) == 0xAE426082;
  }

  static bool _isLegacyWebP(Uint8List bytes) =>
      bytes.length >= 12 &&
      String.fromCharCodes(bytes, 0, 4) == 'RIFF' &&
      String.fromCharCodes(bytes, 8, 12) == 'WEBP' &&
      ByteData.sublistView(bytes).getUint32(4, Endian.little) + 8 ==
          bytes.length;

  static Future<void> _validateImage(Uint8List bytes) async {
    if (bytes.length > _maxBytes) throw const FormatException('校园地图文件过大');
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        if (descriptor.width > 8192 ||
            descriptor.height > 8192 ||
            descriptor.width * descriptor.height > 32000000) {
          throw const FormatException('校园地图尺寸过大');
        }
        final codec = await descriptor.instantiateCodec();
        try {
          if (codec.frameCount != 1) {
            throw const FormatException('校园地图应为静态图片');
          }
          (await codec.getNextFrame()).image.dispose();
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }
}
