import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../network/neuq_web_client.dart';
import '../time/campus_clock.dart';

class SchoolSyncStatus extends StatelessWidget {
  const SchoolSyncStatus({
    super.key,
    required this.available,
    required this.refresh,
    required this.syncedAt,
    required this.label,
    this.cacheError = false,
    this.reconnect,
    this.compactSuccessLabel,
  });

  final bool available;
  final AsyncValue<void> refresh;
  final DateTime? syncedAt;
  final String label;
  final bool cacheError;
  final Widget? reconnect;
  final String? compactSuccessLabel;

  @override
  Widget build(BuildContext context) {
    final time = syncedAt?.toUtc().add(campusOffset);
    final last = time == null
        ? null
        : '${shortDate(time)} ${clockLabel(time.hour * 60 + time.minute)}';
    final failure = refresh.error;
    final needsLogin =
        failure == SchoolWebFailure.expired ||
        failure == SchoolWebFailure.differentAccount;
    final status = !available
        ? '$label待接入'
        : needsLogin
        ? '请重新连接教务${last == null ? '' : ' · 显示 $last 的缓存'}'
        : failure == SchoolWebFailure.denied
        ? '教务暂未开放此查询${last == null ? '' : ' · 显示 $last 的缓存'}'
        : refresh.hasError || cacheError
        ? (last == null ? '$label失败，请重试' : '$label失败 · 显示 $last 的缓存')
        : refresh.isLoading
        ? (last == null ? '正在$label…' : '正在$label · 上次 $last')
        : (last == null ? '尚未$label' : '上次$label $last');
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final compact = compactSuccessLabel != null;
    if (compact &&
        available &&
        !refresh.isLoading &&
        !refresh.hasError &&
        !cacheError &&
        last != null) {
      return Tooltip(
        message: status,
        child: Text(compactSuccessLabel!, style: style),
      );
    }
    return Row(
      children: [
        if (!compact) ...[
          Icon(
            available ? Icons.cloud_outlined : Icons.cloud_off_outlined,
            size: 16,
          ),
          const SizedBox(width: 7),
        ],
        Expanded(child: Text(status, style: style)),
        if (needsLogin) ?reconnect,
      ],
    );
  }
}
