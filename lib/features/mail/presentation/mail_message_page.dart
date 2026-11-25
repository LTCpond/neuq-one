import 'package:material_ui/material_ui.dart';

import '../../../core/time/campus_clock.dart';
import '../../../core/widgets/editor.dart';
import '../../../core/widgets/screen.dart';
import '../data/campus_mail.dart';
import 'mail_compose_page.dart';

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
  late Future<MailDetails> _details = widget.repository.readMessage(
    widget.preview.id,
  );
  late bool _starred = widget.preview.starred;
  bool _busy = false;

  Future<void> _act(Future<void> Function() action, {bool back = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && back) Navigator.pop(context);
    } on FormatException catch (error) {
      if (mounted) showMessage(context, error.message);
    } catch (_) {
      if (mounted) showMessage(context, '操作失败，请检查网络后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _move() async {
    final folders = widget.folders.where(
      (folder) => folder.id != widget.preview.id.folder,
    );
    final destination = await showDialog<MailFolder>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('移动到文件夹'),
        children: [
          for (final folder in folders)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, folder),
              child: Text(folder.name),
            ),
        ],
      ),
    );
    if (destination != null && mounted) {
      await _act(
        () => widget.repository.move(widget.preview.id, destination.id),
        back: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.preview.id;
    final trash = widget.folders
        .where((folder) => folder.trash && folder.id != id.folder)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('邮件详情'),
        actions: [
          IconButton(
            tooltip: _starred ? '取消星标' : '添加星标',
            icon: Icon(_starred ? Icons.star : Icons.star_border),
            onPressed: _busy
                ? null
                : () => _act(() async {
                    await widget.repository.setStarred(id, !_starred);
                    if (mounted) setState(() => _starred = !_starred);
                  }),
          ),
          PopupMenuButton<String>(
            enabled: !_busy,
            onSelected: (action) async {
              switch (action) {
                case 'unread':
                  await _act(
                    () => widget.repository.markUnread(id),
                    back: true,
                  );
                case 'move':
                  await _move();
                case 'trash':
                  if (trash != null &&
                      await confirmAction(
                        context,
                        '移到已删除？',
                        '可从邮箱的「已删除」文件夹找回。',
                      ) &&
                      mounted) {
                    await _act(
                      () => widget.repository.move(id, trash.id),
                      back: true,
                    );
                  }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'unread', child: Text('标为未读')),
              if (widget.folders.length > 1)
                const PopupMenuItem(value: 'move', child: Text('移动到文件夹')),
              if (trash != null)
                const PopupMenuItem(value: 'trash', child: Text('移到已删除')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<MailDetails>(
          future: _details,
          builder: (context, snapshot) {
            final message = snapshot.data;
            if (snapshot.hasError) {
              return StatePanel(
                '无法读取邮件',
                '请检查网络后重试。',
                icon: Icons.error_outline,
                action: OutlinedButton(
                  onPressed: () => setState(
                    () => _details = widget.repository.readMessage(id),
                  ),
                  child: const Text('重试'),
                ),
              );
            }
            if (message == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final preview = message.preview;
            final subject = preview.subject;
            final date = preview.date?.toUtc().add(campusOffset);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
              children: [
                if (_busy) const LinearProgressIndicator(),
                Text(
                  subject.isEmpty ? '（无主题）' : subject,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text('发件人 · ${preview.sender}'),
                if (message.recipients.isNotEmpty)
                  Text('收件人 · ${message.recipients}'),
                if (date != null)
                  Text(
                    '${date.year}年${shortDate(date)} ${clockLabel(date.hour * 60 + date.minute)}',
                  ),
                const Divider(height: 30),
                SelectableText(
                  message.body.isEmpty ? '（无可显示正文）' : message.body,
                ),
                const SizedBox(height: 18),
                for (final attachment in message.attachments)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.attach_file),
                      title: Text(attachment.name),
                      trailing: const Icon(Icons.download_outlined),
                      onTap: _busy
                          ? null
                          : () => _act(() async {
                              final saved = await widget.repository
                                  .saveAttachment(id, attachment);
                              if (saved && context.mounted) {
                                showMessage(context, '附件已保存');
                              }
                            }),
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    if (message.replyTo.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => openMailComposer(
                          context,
                          widget.repository,
                          recipients: message.replyTo,
                          subject: subject.toLowerCase().startsWith('re:')
                              ? subject
                              : 'Re: $subject',
                          inReplyTo: message.messageId,
                        ),
                        icon: const Icon(Icons.reply),
                        label: const Text('回复'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => openMailComposer(
                        context,
                        widget.repository,
                        subject: subject.toLowerCase().startsWith('fwd:')
                            ? subject
                            : 'Fwd: $subject',
                        body:
                            '\n\n转发邮件\n发件人 · ${preview.sender}\n主题 · $subject\n\n${message.body}',
                      ),
                      icon: const Icon(Icons.forward),
                      label: const Text('转发'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
