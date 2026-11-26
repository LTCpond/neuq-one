import 'package:material_ui/material_ui.dart';

import '../../../core/time/campus_clock.dart';
import '../../../core/widgets/editor.dart';
import '../../../core/widgets/screen.dart';
import '../data/campus_mail.dart';
import 'mail_compose_page.dart';
import 'mail_sender_avatar.dart';

class MailMessagePage extends StatefulWidget {
  const MailMessagePage({
    super.key,
    required this.repository,
    required this.preview,
    required this.folders,
  });

  final CampusMailRepository repository;
  final MailPreview preview;
  final List<MailFolder> folders;

  @override
  State<MailMessagePage> createState() => _MailMessagePageState();
}

class _MailMessagePageState extends State<MailMessagePage> {
  late Future<MailDetails> _details = widget.repository.readMessage(id);
  bool? _starred;
  bool _busy = false;

  MailMessageId get id => widget.preview.id;

  Future<void> _act(Future<void> Function() action, {bool back = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && back && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context);
      }
    } on FormatException catch (error) {
      if (mounted) showMessage(context, error.message);
    } catch (_) {
      if (mounted) showMessage(context, '操作失败，请检查网络后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _move() async {
    final destination = await showDialog<MailFolder>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('移动到文件夹'),
        children: [
          for (final folder in widget.folders)
            if (folder.id != id.folder)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, folder),
                child: Text(folder.name),
              ),
        ],
      ),
    );
    if (destination != null && mounted) {
      await _act(() => widget.repository.move(id, destination.id), back: true);
    }
  }

  Future<void> _trash(MailFolder folder) async {
    final confirmed = await confirmAction(
      context,
      '移到已删除？',
      '可从邮箱的「已删除」文件夹找回。',
    );
    if (confirmed && mounted) {
      await _act(() => widget.repository.move(id, folder.id), back: true);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<MailDetails>(
    future: _details,
    builder: (context, snapshot) {
      final message = snapshot.data;
      return Scaffold(
        appBar: _appBar(enabled: message != null && !_busy),
        body: SafeArea(
          top: false,
          child: snapshot.hasError
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    StatePanel(
                      '无法读取邮件',
                      '请检查网络后重试。',
                      icon: Icons.error_outline,
                      action: OutlinedButton(
                        onPressed: () => setState(
                          () => _details = widget.repository.readMessage(id),
                        ),
                        child: const Text('重试'),
                      ),
                    ),
                  ],
                )
              : message == null
              ? const Center(child: CircularProgressIndicator())
              : _messageBody(message),
        ),
        bottomNavigationBar: message == null ? null : _replyBar(message),
      );
    },
  );

  AppBar _appBar({required bool enabled}) {
    final trash = widget.folders
        .where((folder) => folder.trash && folder.id != id.folder)
        .firstOrNull;
    return AppBar(
      actions: [
        if (widget.folders.any((folder) => folder.id != id.folder))
          IconButton(
            tooltip: '移动到文件夹',
            icon: const Icon(Icons.drive_file_move_outlined),
            onPressed: enabled ? _move : null,
          ),
        IconButton(
          tooltip: '标为未读',
          icon: const Icon(Icons.mark_email_unread_outlined),
          onPressed: enabled
              ? () => _act(() => widget.repository.markUnread(id), back: true)
              : null,
        ),
        if (trash != null)
          IconButton(
            tooltip: '移到已删除',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: enabled ? () => _trash(trash) : null,
          ),
      ],
    );
  }

  Widget _messageBody(MailDetails message) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final preview = message.preview;
    final starred = _starred ?? preview.starred;
    final date = preview.date?.toUtc().add(campusOffset);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      children: [
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                preview.subject.isEmpty ? '（无主题）' : preview.subject,
                style: theme.textTheme.headlineSmall,
              ),
            ),
            IconButton(
              tooltip: starred ? '取消星标' : '添加星标',
              isSelected: starred,
              selectedIcon: Icon(Icons.star_rounded, color: colors.primary),
              icon: const Icon(Icons.star_outline_rounded),
              onPressed: _busy
                  ? null
                  : () => _act(() async {
                      await widget.repository.setStarred(id, !starred);
                      if (mounted) setState(() => _starred = !starred);
                    }),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MailSenderAvatar(preview.sender),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(preview.sender, style: theme.textTheme.titleSmall),
                      if (message.recipients.isNotEmpty)
                        Text(
                          '收件人 ${message.recipients}',
                          style: theme.textTheme.bodySmall,
                        ),
                      if (date != null)
                        Text(
                          '${date.year}年${shortDate(date)} ${clockLabel(date.hour * 60 + date.minute)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        SelectableText(
          message.body.isEmpty ? '（无可显示正文）' : message.body,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.55),
        ),
        for (final attachment in message.attachments)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.attach_file),
                title: Text(attachment.name),
                trailing: const Icon(Icons.download_outlined),
                onTap: _busy
                    ? null
                    : () => _act(() async {
                        final saved = await widget.repository.saveAttachment(
                          id,
                          attachment,
                        );
                        if (saved && mounted) showMessage(context, '附件已保存');
                      }),
              ),
            ),
          ),
      ],
    );
  }

  Widget _replyBar(MailDetails message) {
    final subject = message.preview.subject;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (message.replyTo.isNotEmpty)
              FilledButton.tonalIcon(
                onPressed: _busy
                    ? null
                    : () => openMailComposer(
                        context,
                        widget.repository,
                        recipients: message.replyTo,
                        subject: subject.toLowerCase().startsWith('re:')
                            ? subject
                            : 'Re: $subject',
                        inReplyTo: message.messageId,
                      ),
                icon: const Icon(Icons.reply_rounded),
                label: const Text('回复'),
              ),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => openMailComposer(
                      context,
                      widget.repository,
                      subject: subject.toLowerCase().startsWith('fwd:')
                          ? subject
                          : 'Fwd: $subject',
                      body:
                          '\n\n转发邮件\n发件人 · ${message.preview.sender}\n主题 · $subject\n\n${message.body}',
                    ),
              icon: const Icon(Icons.forward_outlined),
              label: const Text('转发'),
            ),
          ],
        ),
      ),
    );
  }
}
