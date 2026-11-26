import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/diagnostics/diagnostics.dart';
import '../../../core/storage/picker_cache.dart';
import '../../services/data/campus_map.dart';
import '../../services/data/classroom_cache.dart';
import '../../services/data/employment_feed.dart';
import '../../services/data/public_classrooms.dart';
import '../../services/data/school_policies.dart';

enum CacheCategory {
  campusMap('校园地图'),
  policies('学校政策目录及 PDF'),
  classrooms('空教室公共数据'),
  employment('就业信息'),
  picker('文件选择器临时文件');

  const CacheCategory(this.label);
  final String label;
}

typedef _CacheActions = ({
  Future<int> Function() size,
  Future<void> Function() clear,
});

final cacheManagerProvider = Provider<CacheManager>((ref) {
  final map = ref.watch(campusMapRepositoryProvider);
  final policies = ref.watch(schoolPolicyRepositoryProvider);
  final classrooms = ref.watch(classroomCacheProvider);
  final employment = ref.watch(employmentRepositoryProvider);
  return CacheManager({
    CacheCategory.campusMap: (
      size: map.cacheBytes,
      clear: () async {
        try {
          await map.clearCache();
        } finally {
          if (ref.mounted) ref.invalidate(campusMapProvider);
        }
      },
    ),
    CacheCategory.policies: (
      size: policies.cacheBytes,
      clear: () async {
        try {
          await policies.clearCache();
        } finally {
          if (ref.mounted) {
            ref.invalidate(schoolPoliciesProvider);
            ref.invalidate(schoolPolicyPdfProvider);
          }
        }
      },
    ),
    CacheCategory.classrooms: (
      size: classrooms.cacheBytes,
      clear: () => ref.read(classroomsProvider.notifier).clearCache(),
    ),
    CacheCategory.employment: (
      size: employment.cacheBytes,
      clear: () async {
        try {
          await employment.clearCache();
        } finally {
          if (ref.mounted) {
            ref.invalidate(employmentCacheProvider);
            ref.invalidate(employmentRefreshProvider);
          }
        }
      },
    ),
    if (pickerCache.supported)
      CacheCategory.picker: (
        size: pickerCache.cacheBytes,
        clear: pickerCache.clearCache,
      ),
  });
});

class CacheManager {
  CacheManager(this._actions);

  final Map<CacheCategory, _CacheActions> _actions;
  Future<Set<CacheCategory>>? _clearing;

  Future<Map<CacheCategory, int?>> sizes() async => Map.fromEntries(
    await Future.wait([
      for (final entry in _actions.entries) _size(entry.key, entry.value),
    ]),
  );

  Future<MapEntry<CacheCategory, int?>> _size(
    CacheCategory category,
    _CacheActions actions,
  ) async {
    try {
      return MapEntry(category, await actions.size());
    } catch (error) {
      diagnostics.record(
        DiagnosticModule.cache,
        DiagnosticStage.read,
        error: error,
      );
      return MapEntry(category, null);
    }
  }

  Future<Set<CacheCategory>> clear([CacheCategory? category]) =>
      _clearing ??= _clear(category).whenComplete(() => _clearing = null);

  Future<Set<CacheCategory>> _clear(CacheCategory? category) async {
    final failures = <CacheCategory>{};
    await Future.wait([
      for (final entry in _actions.entries)
        if (category == null || category == entry.key)
          () async {
            try {
              await entry.value.clear();
            } catch (error) {
              failures.add(entry.key);
              diagnostics.record(
                DiagnosticModule.cache,
                DiagnosticStage.clear,
                error: error,
              );
            }
          }(),
    ]);
    return failures;
  }
}
