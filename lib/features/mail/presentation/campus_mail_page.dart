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

class CampusMailPage extends ConsumerWidget {
  const CampusMailPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(campusMailProvider);
    return repository == null
        ? CampusScreen(
            title: '校园邮箱',
            body: StatePanel(
              '请打开学校邮箱',
              '可在浏览器登录校园邮箱。',
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
  String? _address;
  String? _folder;
  String _query = '';
  int _page = 1;
  MailList? _list;
  String? _error;
  bool _busy = true;
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
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
      if (mounted) setState(() => _error = '连接失败，请检查网络、客户端授权码和 IMAP 设置。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && _address != null) await _load();
  }

  Future<void> _disconnect() async {
    if (!await confirmAction(context, '断开校园邮箱？', '此设备上的邮箱授权码将被移除。') ||
        !mounted ||
        _busy) {
      return;
    }
    try {
      await widget.repository.disconnect();
      if (!mounted) return;
      setState(() {
        _address = null;
        _folder = null;
        _list = null;
        _query = '';
        _error = null;
      });
    } catch (_) {
      if (mounted) showMessage(context, '无法移除邮箱设置，请重试。');
    }
  }

  Future<void> _search() async {
    var query = _query;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('搜索此文件夹'),
        content: TextFormField(
          initialValue: query,
          maxLength: 100,
          autofocus: true,
          decoration: const InputDecoration(labelText: '发件人或主题'),
          onChanged: (value) => query = value,
          onFieldSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, query.trim()),
            child: const Text('搜索'),
          ),
        ],
      ),
    );
    if (!mounted || result == null || result == _query) return;
    setState(() {
      _query = result;
      _list = null;
    });
    await _load();
  }

  Future<void> _showMessage(
    MailPreview message,
    List<MailFolder> folders,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => MailMessagePage(
          repository: widget.repository,
          preview: message,
          folders: folders,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final address = _address;
    final list = _list;
    final folders = list?.folders ?? const <MailFolder>[];
    return CampusScreen(
      title: '校园邮箱',
      eyebrow: address,
      actions: [
        if (address != null) ...[
          IconButton(
            onPressed: _busy ? null : _search,
            tooltip: '搜索邮件',
            icon: const Icon(Icons.search),
          ),
          CampusRefreshButton(
            tooltip: '刷新邮件',
            isLoading: _busy,
            onPressed: _load,
          ),
          PopupMenuButton<String>(
            enabled: !_busy,
            onSelected: (value) {
              if (value == 'disconnect') {
                unawaited(_disconnect());
              } else {
                unawaited(openOfficialPage(context, campusMailWebsite));
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'website', child: Text('打开学校邮箱网页')),
              PopupMenuItem(value: 'disconnect', child: Text('断开邮箱')),
            ],
          ),
        ],
      ],
      floatingActionButton: address == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                await openMailComposer(context, widget.repository);
                if (mounted) await _load();
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('写邮件'),
            ),
      body: _restoring
          ? const Center(child: CircularProgressIndicator())
          : address == null
          ? _MailConnection(busy: _busy, error: _error, connect: _connect)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 92),
              children: [
                if (folders.isNotEmpty)
                  DropdownButton<String>(
                    isExpanded: true,
                    value: list!.folder,
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value == null || value == _folder) return;
                            setState(() {
                              _folder = value;
                              _query = '';
                            });
                            unawaited(_load());
                          },
                    items: [
                      for (final folder in folders)
                        DropdownMenuItem(
                          value: folder.id,
                          child: Text(folder.name),
                        ),
                    ],
                  ),
                if (_query.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InputChip(
                      label: Text(_query),
                      onDeleted: _busy
                          ? null
                          : () {
                              setState(() {
                                _query = '';
                                _list = null;
                              });
                              unawaited(_load());
                            },
                    ),
                  ),
                if (_busy) const LinearProgressIndicator(),
                if (_error case final String error)
                  StatePanel(
                    error,
                    list == null ? '请检查邮箱连接后重试。' : '显示上次加载的邮件。',
                    icon: Icons.error_outline,
                    action: OutlinedButton(
                      onPressed: _load,
                      child: const Text('重试'),
                    ),
                  ),
                if (list != null &&
                    list.messages.isEmpty &&
                    !_busy &&
                    _error == null)
                  StatePanel(
                    _query.isEmpty ? '此文件夹暂无邮件' : '未找到匹配的邮件',
                    '',
                    icon: Icons.inbox_outlined,
                  ),
                if (list != null)
                  for (final message in list.messages)
                    Card(
                      child: ListTile(
                        leading: Icon(
                          message.starred
                              ? Icons.star
                              : message.seen
                              ? Icons.mail_outline
                              : Icons.mark_email_unread_outlined,
                        ),
                        title: Text(
                          message.subject.isEmpty ? '（无主题）' : message.subject,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: message.seen
                              ? null
                              : const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          [
                            message.sender,
                            if (message.date case final DateTime date)
                              shortDate(date.toUtc().add(campusOffset)),
                          ].join(' · '),
                        ),
                        onTap: () => _showMessage(message, folders),
                      ),
                    ),
                if (list?.hasMore == true && !_busy && _error == null)
                  TextButton(
                    onPressed: () => _load(more: true),
                    child: const Text('加载更多'),
                  ),
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
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
    children: [
      const Text(
        '学校邮箱网页可用邮箱密码登录。若要在 App 内收发邮件，请在网页的账号与安全设置中启用 IMAP/SMTP，并生成客户端授权码。',
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => openOfficialPage(context, campusMailWebsite),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text('打开学校邮箱获取授权码'),
        ),
      ),
      TextField(
        controller: _address,
        enabled: !widget.busy,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: '校园邮箱地址',
          hintText: '学号@stu.neuq.edu.cn',
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _code,
        enabled: !widget.busy,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(labelText: '客户端授权码'),
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
