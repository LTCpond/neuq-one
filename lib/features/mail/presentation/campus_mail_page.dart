import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/official_browser.dart';
import '../../../core/time/campus_clock.dart';
import '../../../core/widgets/campus_components.dart';
import '../../../core/widgets/editor.dart';
import '../../../core/widgets/screen.dart';
import '../data/campus_mail.dart';
import 'mail_compose_page.dart';
import 'mail_message_page.dart';
import 'mail_sender_avatar.dart';

class CampusMailPage extends ConsumerWidget {
  const CampusMailPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(campusMailProvider);
    return repository == null
        ? CampusScreen(
            title: '校园邮箱',
            body: StatePanel(
              '东北大学学生邮箱',
              '可在浏览器登录邮箱并收发邮件。',
              icon: Icons.mail_outline,
              action: OutlinedButton(
                onPressed: () => openOfficialPage(context, campusMailWebsite),
                child: const Text('打开学校邮箱'),
              ),
            ),
          )
        : _Mailbox(key: ObjectKey(repository), repository: repository);
  }
}

class _Mailbox extends StatefulWidget {
  const _Mailbox({required this.repository, super.key});
  final CampusMailRepository repository;

  @override
  State<_Mailbox> createState() => _MailboxState();
}

class _MailboxState extends State<_Mailbox> {
  final _searchText = TextEditingController();
  final _selected = <MailMessageId>{};
  String? _address;
  String? _folder;
  String _query = '';
  int _page = 1;
  List<MailFolder> _folders = const [];
  MailList? _list;
  String? _error;
  bool _busy = true;
  bool _restoring = true;

  bool get _selecting => _selected.isNotEmpty;

  MailFolder? get _currentFolder =>
      _folders.where((item) => item.id == _folder).firstOrNull;

  bool get _inTrash => _currentFolder?.trash ?? false;

  bool get _hasTrash => _folders.any((folder) => folder.trash);

  List<MailPreview> get _messages => _list?.messages ?? const [];

  bool get _allSelected =>
      _messages.isNotEmpty && _selected.length >= _messages.length;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  @override
  void dispose() {
    _searchText.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final address = await widget.repository.address();
      if (mounted) setState(() => _address = address);
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取邮箱设置，请重新连接。');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _restoring = false;
        });
      }
    }
    if (mounted && _address != null) await _load();
  }

  Future<void> _load({bool more = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      if (!more) _selected.clear();
    });
    final next = more ? _page + 1 : 1;
    try {
      final result = await widget.repository.list(
        folder: _folder,
        page: next,
        query: _query,
      );
      if (!mounted) return;
      setState(() {
        final messages = {
          if (more)
            for (final item in _list?.messages ?? const <MailPreview>[])
              item.id: item,
          for (final item in result.messages) item.id: item,
        };
        _list = (
          folders: result.folders,
          folder: result.folder,
          messages: messages.values.toList(),
          hasMore: result.hasMore,
        );
        _page = next;
        _folder = result.folder;
        _folders = result.folders;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '无法同步邮件，请检查网络或重新连接邮箱。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect(String address, String code) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.connect(address, code);
      if (mounted) setState(() => _address = address.trim().toLowerCase());
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '连接失败，请检查网络、客户端专用密码和 IMAP 设置。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && _address != null) await _load();
  }

  Future<void> _disconnect() async {
    if (!await confirmAction(context, '断开校园邮箱？', '此设备上的客户端专用密码将被移除。') ||
        !mounted ||
        _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.repository.disconnect();
      if (!mounted) return;
      _searchText.clear();
      setState(() {
        _address = null;
        _folder = null;
        _folders = const [];
        _list = null;
        _query = '';
        _error = null;
        _selected.clear();
      });
    } catch (_) {
      if (mounted) showMessage(context, '无法移除邮箱设置，请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _search(String text) {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    final query = text.trim();
    if (query == _query) return;
    setState(() {
      _query = query;
      _list = null;
    });
    unawaited(_load());
  }

  Future<MailFolder?> _pickFolder({required String title, String? exclude}) {
    FocusScope.of(context).unfocus();
    final options = [
      for (final folder in _folders)
        if (folder.id != exclude) folder,
    ];
    return showModalBottomSheet<MailFolder>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  for (final folder in options)
                    ListTile(
                      leading: Icon(_folderIcon(folder)),
                      title: Text(folder.name),
                      selected: folder.id == _folder,
                      selectedTileColor: Theme.of(context)
                          .colorScheme
                          .primaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onTap: () => Navigator.pop(context, folder),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectFolder() async {
    final folder = await _pickFolder(title: '邮箱文件夹');
    if (!mounted || folder == null || folder.id == _folder || _busy) return;
    _searchText.clear();
    setState(() {
      _folder = folder.id;
      _query = '';
      _list = null;
      _selected.clear();
    });
    await _load();
  }

  /// Runs one mailbox mutation while keeping the list and its actions locked.
  Future<bool> _perform(
    Future<void> Function() operation, {
    String failure = '操作失败，请检查网络后重试。',
  }) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await operation();
      return true;
    } on FormatException catch (error) {
      if (mounted) showMessage(context, error.message);
    } catch (_) {
      if (mounted) showMessage(context, failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return false;
  }

  void _toggleSelected(MailPreview message) {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      if (!_selected.remove(message.id)) _selected.add(message.id);
    });
  }

  void _clearSelection() {
    if (_selected.isEmpty) return;
    setState(_selected.clear);
  }

  void _toggleAll() {
    if (_busy) return;
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        _selected.addAll(_messages.map((message) => message.id));
      }
    });
  }

  void _removeLocally(Iterable<MailMessageId> ids) {
    final list = _list;
    if (list == null) return;
    final removed = ids.toSet();
    setState(() {
      _list = (
        folders: list.folders,
        folder: list.folder,
        messages: [
          for (final message in list.messages)
            if (!removed.contains(message.id)) message,
        ],
        hasMore: list.hasMore,
      );
      _selected.removeAll(removed);
    });
  }

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty || _busy) return;
    final forever = _inTrash;
    if (forever) {
      final confirmed = await confirmAction(
        context,
        '永久删除？',
        '将永久删除 ${ids.length} 封邮件，无法恢复。',
        label: '永久删除',
      );
      if (!confirmed || !mounted) return;
    }
    final done = await _perform(() async {
      await widget.repository.deleteMessages(ids, forever: forever);
      if (mounted) _removeLocally(ids);
    }, failure: '无法删除邮件，请检查网络后重试。');
    if (!done || !mounted) return;
    showMessage(
      context,
      forever
          ? '已永久删除 ${ids.length} 封邮件'
          : _hasTrash
          ? '已将 ${ids.length} 封邮件移到「已删除」'
          : '已删除 ${ids.length} 封邮件',
    );
  }

  Future<void> _moveSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty || _busy) return;
    if (_folders.length < 2) {
      showMessage(context, '没有其他可用的邮箱文件夹。');
      return;
    }
    final target = await _pickFolder(title: '移动到文件夹', exclude: _folder);
    if (target == null || !mounted) return;
    final done = await _perform(() async {
      await widget.repository.moveMessages(ids, target.id);
      if (mounted) _removeLocally(ids);
    }, failure: '无法移动邮件，请检查网络后重试。');
    if (done && mounted) {
      showMessage(context, '已将 ${ids.length} 封邮件移到「${target.name}」');
    }
  }

  Future<bool> _swipeAway(MailPreview message) async {
    if (_busy || _selecting) return false;
    final forever = _inTrash;
    if (forever) {
      final confirmed = await confirmAction(
        context,
        '永久删除？',
        '将永久删除「${message.subject.isEmpty ? '（无主题）' : message.subject}」，无法恢复。',
        label: '永久删除',
      );
      if (!confirmed || !mounted) return false;
    }
    final done = await _perform(
      () => widget.repository.deleteMessages([message.id], forever: forever),
      failure: '无法删除邮件，请检查网络后重试。',
    );
    if (!done || !mounted) return false;
    showMessage(
      context,
      forever
          ? '邮件已永久删除'
          : _hasTrash
          ? '邮件已移到「已删除」'
          : '邮件已删除',
    );
    return true;
  }

  Future<void> _toggleStar(MailPreview message) async {
    if (_busy) return;
    final messages = _list?.messages;
    if (messages == null) return;
    final index = messages.indexWhere((item) => item.id == message.id);
    if (index < 0) return;

    setState(() => _busy = true);
    try {
      await widget.repository.setStarred(message.id, !message.starred);
      if (!mounted) return;
      setState(() {
        messages[index] = (
          id: message.id,
          sender: message.sender,
          subject: message.subject,
          date: message.date,
          seen: message.seen,
          starred: !message.starred,
        );
      });
    } catch (_) {
      if (mounted) showMessage(context, '无法更新星标，请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showMessage(MailPreview message) async {
    FocusScope.of(context).unfocus();
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => MailMessagePage(
          repository: widget.repository,
          preview: message,
          folders: _folders,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final address = _address;
    if (address == null) {
      return CampusScreen(
        title: '校园邮箱',
        body: _restoring
            ? const Center(child: CircularProgressIndicator())
            : _MailConnection(busy: _busy, error: _error, connect: _connect),
      );
    }

    final colors = Theme.of(context).colorScheme;
    final list = _list;
    final folder = _folders.where((item) => item.id == _folder).firstOrNull;
    final folderName = folder?.name ?? '收件箱';
    final deleteLabel = _inTrash
        ? '永久删除'
        : _hasTrash
        ? '移到已删除'
        : '删除';
    final searchBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
    );

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
      },
      child: Scaffold(
        appBar: _selecting
            ? AppBar(
                leading: IconButton(
                  tooltip: '退出多选',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _busy ? null : _clearSelection,
                ),
                title: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('已选 ${_selected.length} 封'),
                ),
                actions: [
                  IconButton(
                    tooltip: _allSelected ? '取消全选' : '全选',
                    icon: Icon(
                      _allSelected
                          ? Icons.deselect_rounded
                          : Icons.select_all_rounded,
                    ),
                    onPressed: _busy ? null : _toggleAll,
                  ),
                  IconButton(
                    tooltip: '移动到文件夹',
                    icon: const Icon(Icons.drive_file_move_outlined),
                    onPressed: _busy ? null : _moveSelected,
                  ),
                  IconButton(
                    tooltip: deleteLabel,
                    icon: Icon(
                      _inTrash
                          ? Icons.delete_forever_outlined
                          : Icons.delete_outline_rounded,
                    ),
                    onPressed: _busy ? null : _deleteSelected,
                  ),
                ],
              )
            : AppBar(
                title: const Text('校园邮箱'),
                actions: [
                  CampusRefreshButton(
                    tooltip: '刷新邮件',
                    isLoading: _busy,
                    onPressed: _load,
                  ),
                  PopupMenuButton<String>(
                    tooltip: '邮箱设置',
                    icon: const Icon(Icons.account_circle_outlined),
                    enabled: !_busy,
                    onSelected: (value) {
                      if (value == 'disconnect') {
                        unawaited(_disconnect());
                      } else {
                        unawaited(openOfficialPage(context, campusMailWebsite));
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        enabled: false,
                        child: Text(
                          address,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'website',
                        child: Text('打开学校邮箱网页'),
                      ),
                      const PopupMenuItem(
                        value: 'disconnect',
                        child: Text('断开邮箱'),
                      ),
                    ],
                  ),
                ],
              ),
        floatingActionButton: _selecting
            ? null
            : FloatingActionButton.extended(
                onPressed: _busy
                    ? null
                    : () async {
                        FocusScope.of(context).unfocus();
                        await openMailComposer(context, widget.repository);
                        if (mounted) await _load();
                      },
                backgroundColor: colors.primaryContainer,
                foregroundColor: colors.onPrimaryContainer,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('写邮件'),
              ),
        body: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_selecting) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: TextField(
                    controller: _searchText,
                    readOnly: _busy,
                    maxLength: 100,
                    textInputAction: TextInputAction.search,
                    onSubmitted: _search,
                    style: Theme.of(context).textTheme.bodyMedium,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '搜索发件人或主题',
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      fillColor: colors.surface,
                      border: searchBorder,
                      enabledBorder: searchBorder.copyWith(
                        borderSide: BorderSide(color: colors.outlineVariant),
                      ),
                      prefixIcon: IconButton(
                        tooltip: '搜索邮件',
                        onPressed: _busy
                            ? null
                            : () => _search(_searchText.text),
                        icon: const Icon(Icons.search_rounded),
                      ),
                      suffixIcon: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _searchText,
                        builder: (context, value, child) => value.text.isEmpty
                            ? const SizedBox.shrink()
                            : IconButton(
                                tooltip: '清除搜索',
                                onPressed: _busy
                                    ? null
                                    : () {
                                        _searchText.clear();
                                        _search('');
                                      },
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  child: Row(
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 190),
                        child: Tooltip(
                          message: '切换邮箱文件夹',
                          child: OutlinedButton(
                            onPressed: _busy || _folders.isEmpty
                                ? null
                                : _selectFolder,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 36),
                              padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              shape: const StadiumBorder(),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_folderIcon(folder), size: 17),
                                const SizedBox(width: 7),
                                Flexible(
                                  child: Text(
                                    folderName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                const Icon(Icons.expand_more_rounded, size: 17),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (_messages.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.touch_app_outlined,
                              size: 14,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '长按多选',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      if (_error case final String error)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          sliver: SliverToBoxAdapter(
                            child: StatePanel(
                              error,
                              list == null ? '请检查邮箱连接后重试。' : '显示上次加载的邮件。',
                              icon: Icons.error_outline,
                              action: OutlinedButton(
                                onPressed: _load,
                                child: const Text('重试'),
                              ),
                            ),
                          ),
                        ),
                      if (list != null &&
                          list.messages.isEmpty &&
                          !_busy &&
                          _error == null)
                        SliverPadding(
                          padding: const EdgeInsets.all(16),
                          sliver: SliverToBoxAdapter(
                            child: StatePanel(
                              _query.isEmpty ? '此文件夹暂无邮件' : '未找到匹配的邮件',
                              _query.isEmpty ? '下拉可以重新同步。' : '换个关键词试试。',
                              icon: _query.isEmpty
                                  ? Icons.inbox_outlined
                                  : Icons.search_off_outlined,
                            ),
                          ),
                        ),
                      if (list != null)
                        SliverList.builder(
                          itemCount: list.messages.length,
                          itemBuilder: (context, index) {
                            final message = list.messages[index];
                            final row = _MailRow(
                              message: message,
                              selecting: _selecting,
                              selected: _selected.contains(message.id),
                              open: _busy || _selecting
                                  ? null
                                  : () => _showMessage(message),
                              toggleStar: _busy || _selecting
                                  ? null
                                  : () => _toggleStar(message),
                              onSelect: () => _toggleSelected(message),
                            );
                            if (_selecting) {
                              return KeyedSubtree(
                                key: ValueKey(message.id),
                                child: row,
                              );
                            }
                            return Dismissible(
                              key: ValueKey(message.id),
                              direction: DismissDirection.endToStart,
                              dismissThresholds: const {
                                DismissDirection.endToStart: .35,
                              },
                              background: _SwipeDeleteBackground(
                                permanent: _inTrash,
                              ),
                              confirmDismiss: (_) => _swipeAway(message),
                              onDismissed: (_) => _removeLocally([message.id]),
                              child: row,
                            );
                          },
                        ),
                      if (list?.hasMore == true && !_busy && _error == null)
                        SliverToBoxAdapter(
                          child: Center(
                            child: TextButton(
                              onPressed: () => _load(more: true),
                              child: const Text('加载更多'),
                            ),
                          ),
                        ),
                      const SliverToBoxAdapter(child: SizedBox(height: 88)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _folderIcon(MailFolder? folder) {
  if (folder == null || folder.inbox) return Icons.inbox_outlined;
  if (folder.trash) return Icons.delete_outline_rounded;
  return switch (folder.name) {
    '已发送' => Icons.send_outlined,
    '草稿箱' => Icons.drafts_outlined,
    '垃圾邮件' => Icons.report_gmailerrorred_outlined,
    _ => Icons.folder_outlined,
  };
}

class _MailRow extends StatelessWidget {
  const _MailRow({
    required this.message,
    required this.selecting,
    required this.selected,
    required this.open,
    required this.toggleStar,
    required this.onSelect,
  });

  final MailPreview message;
  final bool selecting;
  final bool selected;
  final VoidCallback? open;
  final VoidCallback? toggleStar;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final unread = !message.seen;
    final date = message.date?.toUtc().add(campusOffset);
    final time = date == null
        ? null
        : calendarDate(date) == calendarDate(campusNow())
        ? clockLabel(date.hour * 60 + date.minute)
        : shortDate(date);
    final background = selected
        ? Color.alphaBlend(
            colors.primary.withValues(alpha: .12),
            colors.surface,
          )
        : unread
        ? Color.alphaBlend(
            colors.primaryContainer.withValues(alpha: .38),
            colors.surface,
          )
        : colors.surface;

    return Material(
      color: background,
      child: Column(
        children: [
          InkWell(
            onTap: selecting ? onSelect : open,
            onLongPress: onSelect,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(
                children: [
                  if (selecting)
                    _SelectionMark(selected: selected)
                  else
                    MailSenderAvatar(message.sender),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 13,
                              child: unread
                                  ? Semantics(
                                      label: '未读邮件',
                                      child: Align(
                                        alignment:
                                            AlignmentDirectional.centerStart,
                                        child: Container(
                                          width: 7,
                                          height: 7,
                                          decoration: BoxDecoration(
                                            color: colors.primary,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                            Expanded(
                              child: Text(
                                message.sender,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: unread
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  color: unread
                                      ? colors.onSurface
                                      : colors.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (time != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                time,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          message.subject.isEmpty ? '（无主题）' : message.subject,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: unread
                                ? colors.onSurface
                                : colors.onSurfaceVariant,
                            fontWeight: unread
                                ? FontWeight.w600
                                : FontWeight.w400,
                            height: 1.35,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (selecting)
                    const SizedBox(width: 8)
                  else
                    IconButton(
                      tooltip: message.starred ? '取消星标' : '添加星标',
                      isSelected: message.starred,
                      selectedIcon: Icon(
                        Icons.star_rounded,
                        color: colors.primary,
                      ),
                      icon: const Icon(Icons.star_outline_rounded),
                      onPressed: toggleStar,
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, indent: 68),
        ],
      ),
    );
  }
}

class _SelectionMark extends StatelessWidget {
  const _SelectionMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      checked: selected,
      label: '选择邮件',
      child: SizedBox.square(
        dimension: 40,
        child: Center(
          child: Icon(
            selected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked,
            size: 24,
            color: selected ? colors.primary : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _SwipeDeleteBackground extends StatelessWidget {
  const _SwipeDeleteBackground({required this.permanent});

  final bool permanent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.errorContainer,
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                permanent
                    ? Icons.delete_forever_rounded
                    : Icons.delete_outline_rounded,
                color: colors.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Text(
                permanent ? '永久删除' : '删除',
                style: TextStyle(
                  color: colors.onErrorContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MailConnection extends StatefulWidget {
  const _MailConnection({
    required this.busy,
    required this.error,
    required this.connect,
  });
  final bool busy;
  final String? error;
  final Future<void> Function(String address, String code) connect;

  @override
  State<_MailConnection> createState() => _MailConnectionState();
}

class _MailConnectionState extends State<_MailConnection> {
  final _address = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    _address.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.mail_outline_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 10),
              Text('连接东北大学学生邮箱', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('在学校邮箱网页设置中启用 IMAP/SMTP，并生成客户端专用密码。'),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () => openOfficialPage(context, campusMailWebsite),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('打开学校邮箱网页'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _address,
        enabled: !widget.busy,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: '校园邮箱地址',
          hintText: '用户名@mails.neu.edu.cn',
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _code,
        enabled: !widget.busy,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(labelText: '客户端专用密码'),
      ),
      const SizedBox(height: 12),
      if (widget.error case final String error)
        Text(
          error,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (widget.busy) const LinearProgressIndicator(),
      FilledButton(
        onPressed: widget.busy
            ? null
            : () => widget.connect(_address.text, _code.text),
        child: const Text('连接校园邮箱'),
      ),
    ],
  );
}
