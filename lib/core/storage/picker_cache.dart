import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'cache_files.dart';

final pickerCache = PickerCache();

class PickerCache {
  int _users = 0;
  bool _clearing = false;

  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<T> run<T>(Future<T> Function() pick) async {
    final release = retain();
    try {
      return await pick();
    } finally {
      release();
    }
  }

  // A mail draft can remain open in another tab and still need the picked files.
  void Function() retain() {
    if (_clearing) throw const FileSystemException('正在清理文件选择器缓存');
    _users++;
    return () => _users--;
  }

  Future<Directory> _directory() async => Directory.fromUri(
    (await getTemporaryDirectory()).uri.resolve(
      defaultTargetPlatform == TargetPlatform.android
          ? 'file_picker/'
          : 'flutter_file_picker/',
    ),
  );

  Future<int> cacheBytes() async =>
      supported ? cacheFileBytes(await _directory()) : 0;

  Future<void> clearCache() async {
    if (!supported) return;
    if (_users > 0 || _clearing) {
      throw const FileSystemException('文件选择器正在使用');
    }
    _clearing = true;
    try {
      final directory = await _directory();
      if (!await directory.exists()) return;
      await FilePicker.clearTemporaryFiles();
      if (await directory.exists() &&
          !await directory.list(followLinks: false).isEmpty) {
        throw const FileSystemException('部分文件选择器缓存无法清除');
      }
    } finally {
      _clearing = false;
    }
  }
}
