import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/widgets/screen.dart';
import '../data/campus_mail.dart';

Future<void> openMailComposer(
  BuildContext context,
  CampusMailRepository repository, {
  String recipients = '',
  String subject = '',
  String body = '',
  String? inReplyTo,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (context) => _MailComposePage(
      repository: repository,
      recipients: recipients,
      subject: subject,
      body: body,
      inReplyTo: inReplyTo,
    ),
  ),
);

class _MailComposePage extends StatefulWidget {
  const _MailComposePage({
    required this.repository,
    required this.recipients,
    required this.subject,
    required this.body,
    this.inReplyTo,
  });

  final CampusMailRepository repository;
  final String recipients;
  final String subject;
  final String body;
  final String? inReplyTo;

  @override
  State<_MailComposePage> createState() => _MailComposePageState();
}

class _MailComposePageState extends State<_MailComposePage> {
  late final _to = TextEditingController(text: widget.recipients);
  final _cc = TextEditingController();
  final _bcc = TextEditingController();
  late final _subject = TextEditingController(text: widget.subject);
  late final _body = TextEditingController(text: widget.body);
  final _attachments = <PlatformFile>[];
  bool _more = false;
  bool _sending = false;
  bool _picking = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_to, _cc, _bcc, _subject, _body]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _attach() async {
    setState(() => _picking = true);
    try {
      final files = await pickMailAttachments();
      if (mounted) setState(() => _attachments.addAll(files));
    } catch (_) {
      if (mounted) showMessage(context, '无法读取所选附件。');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final stored = await widget.repository.send(
        recipients: _to.text,
        cc: _cc.text,
        bcc: _bcc.text,
        subject: _subject.text,
        body: _body.text,
        attachments: _attachments,
        inReplyTo: widget.inReplyTo,
      );
      if (!mounted) return;
      setState(() => _sending = false);
      showMessage(context, stored ? '邮件已发送' : '邮件已发送，已发送文件夹中的副本未保存');
      Navigator.pop(context);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '未能确认邮件已发送，请检查网络和邮箱授权。');
    } finally {
      if (mounted && _sending) setState(() => _sending = false);
    }
  }

  Widget _address(TextEditingController controller, String label) => TextField(
    controller: controller,
    keyboardType: TextInputType.emailAddress,
    textInputAction: TextInputAction.next,
    enabled: !_sending,
    autocorrect: false,
    decoration: _decoration(label),
  );

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    border: InputBorder.none,
    filled: false,
    contentPadding: const EdgeInsets.symmetric(vertical: 14),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_sending,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('写邮件'),
        actions: [
          IconButton(
            tooltip: '添加附件',
            onPressed: _sending || _picking ? null : _attach,
            icon: const Icon(Icons.attach_file),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _sending || _picking ? null : _send,
              child: const Text('发送'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            if (_sending) const LinearProgressIndicator(),
            Row(
              children: [
                Expanded(child: _address(_to, '收件人')),
                Semantics(
                  expanded: _more,
                  child: TextButton(
                    onPressed: _sending
                        ? null
                        : () => setState(() => _more = !_more),
                    child: const Text('抄送／密送'),
                  ),
                ),
              ],
            ),
            const Divider(height: 1),
            if (_more) ...[
              _address(_cc, '抄送'),
              const Divider(height: 1),
              _address(_bcc, '密送'),
              const Divider(height: 1),
            ],
            TextField(
              controller: _subject,
              enabled: !_sending,
              maxLength: 250,
              textInputAction: TextInputAction.next,
              decoration: _decoration('主题').copyWith(counterText: ''),
            ),
            const Divider(height: 1),
            TextField(
              controller: _body,
              enabled: !_sending,
              keyboardType: TextInputType.multiline,
              minLines: 8,
              maxLines: null,
              decoration: _decoration('正文').copyWith(alignLabelWithHint: true),
            ),
            for (final file in _attachments)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.attach_file),
                    title: Text(
                      file.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      tooltip: '移除附件',
                      icon: const Icon(Icons.close),
                      onPressed: _sending
                          ? null
                          : () => setState(() => _attachments.remove(file)),
                    ),
                  ),
                ),
              ),
            if (_error case final String error)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
