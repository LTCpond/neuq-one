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
              '东北大学本部学生邮箱',
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
  String? _address;
  String? _folder;
  String _query = '';
  int _page = 1;
  List<MailFolder> _folders = const [];
  MailList? _list;
  String? _error;
  bool _busy = true;
  bool _restoring = true;

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

  Future<void> _selectFolder() async {
    FocusScope.of(context).unfocus();
    final folder = await showModalBottomSheet<MailFolder>(
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
              child: Text(
                '邮箱文件夹',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  for (final folder in _folders)
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
    if (!mounted || folder == null || folder.id == _folder || _busy) return;
    _searchText.clear();
    setState(() {
      _folder = folder.id;
      _query = '';
      _list = null;
    });
    await _load();
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
    final searchBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
    );

    return Scaffold(
      appBar: AppBar(
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
              const PopupMenuItem(value: 'website', child: Text('打开学校邮箱网页')),
              const PopupMenuItem(value: 'disconnect', child: Text('断开邮箱')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _searchText,
                readOnly: _busy,
                maxLength: 100,
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: '搜索发件人或主题',
                  counterText: '',
                  fillColor: colors.surface,
                  border: searchBorder,
                  enabledBorder: searchBorder.copyWith(
                    borderSide: BorderSide(color: colors.outlineVariant),
                  ),
                  prefixIcon: IconButton(
                    tooltip: '搜索邮件',
                    onPressed: _busy ? null : () => _search(_searchText.text),
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
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Tooltip(
                  message: '切换邮箱文件夹',
                  child: OutlinedButton(
                    onPressed: _busy || _folders.isEmpty ? null : _selectFolder,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_folderIcon(folder), size: 18),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            folderName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.expand_more_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
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
                            '',
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
                          return _MailRow(
                            key: ValueKey(message.id),
                            message: message,
                            open: _busy ? null : () => _showMessage(message),
                            toggleStar: _busy
                                ? null
                                : () => _toggleStar(message),
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
    super.key,
    required this.message,
    required this.open,
    required this.toggleStar,
  });

  final MailPreview message;
  final VoidCallback? open;
  final VoidCallback? toggleStar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final date = message.date?.toUtc().add(campusOffset);
    final time = date == null
        ? null
        : calendarDate(date) == calendarDate(campusNow())
        ? clockLabel(date.hour * 60 + date.minute)
        : shortDate(date);
    final sender = theme.textTheme.titleSmall?.copyWith(
      fontWeight: message.seen ? FontWeight.w500 : FontWeight.w800,
    );
    final subject = theme.textTheme.bodyMedium?.copyWith(
      color: message.seen ? colors.onSurfaceVariant : colors.onSurface,
      fontWeight: message.seen ? FontWeight.w400 : FontWeight.w600,
    );

    return Material(
      color: message.seen
          ? colors.surface
          : Color.alphaBlend(
              colors.primaryContainer.withValues(alpha: .32),
              colors.surface,
            ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: message.seen ? null : '未读',
                  child: InkWell(
                    onTap: open,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                      child: Row(
                        children: [
                          MailSenderAvatar(message.sender),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  message.sender,
                                  style: sender,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  message.subject.isEmpty
                                      ? '（无主题）'
                                      : message.subject,
                                  style: subject,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (time != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          time,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
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
            ],
          ),
          const Divider(height: 1, indent: 68),
        ],
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
              Text('连接本部学生邮箱', style: Theme.of(context).textTheme.titleLarge),
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
