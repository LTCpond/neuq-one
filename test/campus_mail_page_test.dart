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
      await tester.pumpWidget(
        ProviderScope(
          overrides: [campusMailProvider.overrideWithValue(repository)],
          child: MaterialApp(
            theme: appTheme(Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.3)),
              child: child!,
            ),
            home: const CampusMailPage(),
          ),
        ),
      );
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
}

const _inbox = (id: 'INBOX', name: '收件箱', inbox: true, trash: false);
const _sent = (id: 'Sent', name: '已发送', inbox: false, trash: false);
const _noticeId = (folder: 'INBOX', validity: 1, uid: 1);

class _TestMailbox extends CampusMailRepository {
  _TestMailbox() : super(const FlutterSecureStorage(), 'test');

  bool starred = false;
  bool markedUnread = false;
  String? lastFolder;
  String? lastQuery;
  String? replyMessageId;
  String? replyRecipients;
  String? replySubject;

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
    return (
      folders: [_inbox, _sent],
      folder: folder ?? _inbox.id,
      messages: [
        if (folder != _sent.id) _notice,
        if (folder != _sent.id && query.isEmpty)
          (
            id: (folder: 'INBOX', validity: 1, uid: 2),
            sender: '图书馆',
            subject: '预约确认',
            date: null,
            seen: true,
            starred: false,
          ),
      ],
      hasMore: false,
    );
  }

  @override
  Future<void> setStarred(MailMessageId id, bool value) async {
    expect(id, _noticeId);
    starred = value;
  }

  @override
  Future<void> markUnread(MailMessageId id) async {
    expect(id, _noticeId);
    markedUnread = true;
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
