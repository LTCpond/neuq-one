import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:neuq_one/core/theme/app_theme.dart';
import 'package:neuq_one/features/mail/data/campus_mail.dart';
import 'package:neuq_one/features/mail/presentation/campus_mail_page.dart';

void main() {
  testWidgets(
    'mailbox search, stars, folders and replies work on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repository = _TestMailbox();
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();
      expect(find.text('课程通知'), findsOneWidget);
      expect(find.text('预约确认'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '课程');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(repository.lastQuery, '课程');
      expect(find.text('课程通知'), findsOneWidget);
      expect(find.text('预约确认'), findsNothing);

      await tester.tap(find.byTooltip('添加星标'));
      await tester.pumpAndSettle();
      expect(repository.starred, isTrue);
      expect(find.byTooltip('取消星标'), findsOneWidget);

      await tester.tap(find.text('课程通知'));
      await tester.pumpAndSettle();
      expect(find.text('课程安排见正文'), findsOneWidget);
      expect(find.byTooltip('标为未读'), findsOneWidget);
      expect(find.text('转发'), findsOneWidget);

      await tester.tap(find.text('回复'));
      await tester.pumpAndSettle();
      expect(find.text('sender@example.com'), findsOneWidget);
      expect(find.text('Re: 课程通知'), findsOneWidget);

      await tester.tap(find.text('抄送／密送'));
      await tester.pumpAndSettle();
      expect(find.text('抄送'), findsOneWidget);
      expect(find.text('密送'), findsOneWidget);
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(repository.replyMessageId, '<lesson@example.com>');
      expect(repository.replyRecipients, 'sender@example.com');
      expect(repository.replySubject, 'Re: 课程通知');

      await tester.tap(find.byTooltip('标为未读'));
      await tester.pumpAndSettle();
      expect(repository.markedUnread, isTrue);
      expect(find.text('课程通知'), findsOneWidget);

      await tester.tap(find.byTooltip('切换邮箱文件夹'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('已发送'));
      await tester.pumpAndSettle();
      expect(repository.lastFolder, _sent.id);
      expect(repository.lastQuery, isEmpty);
      expect(find.text('课程通知'), findsNothing);
      expect(find.text('此文件夹暂无邮件'), findsOneWidget);
    },
  );

  testWidgets('swiping a mail left moves it to the trash folder', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = _TestMailbox();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await tester.drag(find.text('课程通知'), const Offset(-400, 0));
    await tester.pumpAndSettle();

    expect(repository.deleted.map((id) => id.uid), [1]);
    expect(repository.deletedForever, isFalse);
    expect(find.text('课程通知'), findsNothing);
    expect(find.text('预约确认'), findsOneWidget);
    expect(find.text('邮件已移到「已删除」'), findsOneWidget);
  });

  testWidgets('long press selects mails for batch move', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = _TestMailbox();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('课程通知'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 封'), findsOneWidget);
    expect(find.byTooltip('退出多选'), findsOneWidget);

    await tester.tap(find.text('预约确认'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 封'), findsOneWidget);

    await tester.tap(find.byTooltip('移动到文件夹'));
    await tester.pumpAndSettle();
    expect(find.text('已发送'), findsOneWidget);
    await tester.tap(find.text('已发送'));
    await tester.pumpAndSettle();

    expect(repository.movedTo, _sent.id);
    expect(repository.moved.map((id) => id.uid), [1, 2]);
    expect(find.text('课程通知'), findsNothing);
    expect(find.text('预约确认'), findsNothing);
    expect(find.text('成绩单'), findsOneWidget);
    expect(find.text('已选 2 封'), findsNothing);
    expect(find.text('长按多选'), findsOneWidget);
  });

  testWidgets('selected mails can be moved to the trash in one batch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = _TestMailbox();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('课程通知'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 3 封'), findsOneWidget);

    await tester.tap(find.byTooltip('移到已删除'));
    await tester.pumpAndSettle();

    expect(repository.deleted.map((id) => id.uid), [1, 2, 3]);
    expect(repository.deletedForever, isFalse);
    expect(find.text('已将 3 封邮件移到「已删除」'), findsOneWidget);
    expect(find.text('已选 3 封'), findsNothing);
  });

  testWidgets('mail in the trash folder is deleted only after confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = _TestMailbox();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('切换邮箱文件夹'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已删除'));
    await tester.pumpAndSettle();
    expect(repository.lastFolder, _trash.id);

    await tester.drag(find.text('课程通知'), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('永久删除？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '永久删除'));
    await tester.pumpAndSettle();

    expect(repository.deletedForever, isTrue);
    expect(find.text('课程通知'), findsNothing);
  });
}

Widget _app(CampusMailRepository repository) => ProviderScope(
  overrides: [campusMailProvider.overrideWithValue(repository)],
  child: MaterialApp(
    theme: appTheme(Brightness.dark),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: const TextScaler.linear(1.3)),
      child: child!,
    ),
    home: const CampusMailPage(),
  ),
);

const _inbox = (id: 'INBOX', name: '收件箱', inbox: true, trash: false);
const _sent = (id: 'Sent', name: '已发送', inbox: false, trash: false);
const _trash = (id: 'Trash', name: '已删除', inbox: false, trash: true);
const _noticeId = (folder: 'INBOX', validity: 1, uid: 1);

class _TestMailbox extends CampusMailRepository {
  _TestMailbox() : super(const FlutterSecureStorage(), 'test');

  bool starred = false;
  bool markedUnread = false;
  bool deletedForever = false;
  String? lastFolder;
  String? lastQuery;
  String? replyMessageId;
  String? replyRecipients;
  String? replySubject;
  String? movedTo;
  final deleted = <MailMessageId>[];
  final moved = <MailMessageId>[];

  MailPreview get _notice => (
    id: _noticeId,
    sender: '课程中心',
    subject: '课程通知',
    date: DateTime.utc(2026, 11, 20, 1, 30),
    seen: false,
    starred: starred,
  );

  @override
  Future<String?> address() async => 'student@mails.neu.edu.cn';

  @override
  Future<MailList> list({
    String? folder,
    int page = 1,
    String query = '',
  }) async {
    lastFolder = folder;
    lastQuery = query;
    final path = folder ?? _inbox.id;
    final messages = path == _sent.id
        ? const <MailPreview>[]
        : [
            _notice,
            if (query.isEmpty)
              (
                id: (folder: path, validity: 1, uid: 2),
                sender: '图书馆',
                subject: '预约确认',
                date: null,
                seen: true,
                starred: false,
              ),
            if (query.isEmpty)
              (
                id: (folder: path, validity: 1, uid: 3),
                sender: '教务处',
                subject: '成绩单',
                date: null,
                seen: true,
                starred: false,
              ),
          ];
    return (
      folders: [_inbox, _sent, _trash],
      folder: path,
      messages: messages,
      hasMore: false,
    );
  }

  @override
  Future<void> setStarred(MailMessageId id, bool value) async {
    expect(id.uid, _noticeId.uid);
    starred = value;
  }

  @override
  Future<void> markUnread(MailMessageId id) async {
    expect(id, _noticeId);
    markedUnread = true;
  }

  @override
  Future<void> deleteMessages(
    Iterable<MailMessageId> ids, {
    bool forever = false,
  }) async {
    deleted.addAll(ids);
    deletedForever = forever;
  }

  @override
  Future<void> moveMessages(Iterable<MailMessageId> ids, String target) async {
    moved.addAll(ids);
    movedTo = target;
  }

  @override
  Future<MailDetails> readMessage(MailMessageId id) async => (
    preview: _notice,
    recipients: 'student@mails.neu.edu.cn',
    body: '课程安排见正文',
    replyTo: 'sender@example.com',
    messageId: '<lesson@example.com>',
    attachments: const <MailAttachment>[],
  );

  @override
  Future<bool> send({
    required String recipients,
    required String cc,
    required String bcc,
    required String subject,
    required String body,
    required List<PlatformFile> attachments,
    String? inReplyTo,
  }) async {
    replyMessageId = inReplyTo;
    replyRecipients = recipients;
    replySubject = subject;
    return true;
  }
}
