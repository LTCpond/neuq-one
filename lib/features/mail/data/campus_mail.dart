import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:enough_mail/enough_mail.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/storage/picker_cache.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../../../core/auth/school_auth.dart';

const campusMailWebsite = 'https://mails.neu.edu.cn/';
const _mailServer = 'uni-edu.icoremail.net';
const _mailLimit = 15 * 1024 * 1024;
const _pageSize = 25;
const _responseTimeout = Duration(seconds: 20);
final _studentMailAddress = RegExp(
  r'^[a-z0-9][a-z0-9._+-]{0,63}@(mails|stu)\.neu\.edu\.cn$',
);

final campusMailProvider = Provider<CampusMailRepository?>((ref) {
  final subject = ref.watch(
    schoolSessionProvider.select((state) => state.asData?.value?.subject),
  );
  if (subject == null || kIsWeb) return null;
  return CampusMailRepository(ref.watch(schoolTicketStorageProvider), subject);
});

typedef MailFolder = ({String id, String name, bool inbox, bool trash});
typedef MailMessageId = ({String folder, int validity, int uid});
typedef MailList = ({
  List<MailFolder> folders,
  String folder,
  List<MailPreview> messages,
  bool hasMore,
});
typedef MailPreview = ({
  MailMessageId id,
  String subject,
  String sender,
  DateTime? date,
  bool seen,
  bool starred,
});
typedef MailAttachment = ({String id, String name, int? bytes});
typedef MailDetails = ({
  MailPreview preview,
  String recipients,
  String body,
  String replyTo,
  String? messageId,
  List<MailAttachment> attachments,
});

class CampusMailRepository {
  CampusMailRepository(this._storage, String subject)
    : _key = 'campusMailbox:$subject';

  final FlutterSecureStorage _storage;
  final String _key;

  Future<String?> address() async => (await _stored())?.address;

  Future<void> connect(String address, String code) async {
    final normalized = address.trim().toLowerCase();
    final secret = code.trim();
    if (!_studentMailAddress.hasMatch(normalized)) {
      throw const FormatException(
        '请输入完整的本部学生邮箱地址（@mails.neu.edu.cn 或 @stu.neu.edu.cn）',
      );
    }
    if (secret.length < 6 ||
        secret.length > 128 ||
        RegExp(r'\s').hasMatch(secret)) {
      throw const FormatException('请输入邮箱网页生成的客户端专用密码');
    }
    await _open((address: normalized, code: secret), (client) async {
      await client.selectInbox();
    });
    await _storage.write(key: _key, value: jsonEncode([normalized, secret]));
  }

  Future<void> disconnect() => _storage.delete(key: _key);

  Future<MailList> list({String? folder, int page = 1, String query = ''}) =>
      _read((client) async {
        final folders = [
          for (final item in await client.listMailboxes())
            if (!item.isNotSelectable) _folder(item),
        ];
        final selected = folder == null
            ? await client.selectInbox()
            : await client.selectMailboxByPath(folder);
        final List<MimeMessage> messages;
        final bool hasMore;
        if (query.isNotEmpty) {
          final result = await client.searchMessages(
            MailSearch(
              query,
              SearchQueryType.fromOrSubject,
              pageSize: _pageSize,
            ),
          );
          messages = result.messages.toList();
          for (var index = 1; index < page; index++) {
            messages.addAll(await client.searchMessagesNextPage(result));
          }
          hasMore = result.hasMoreResults;
        } else {
          if (selected.messagesExists == 0) {
            messages = const [];
          } else {
            messages = await client.fetchMessages(
              page: page,
              count: _pageSize,
              fetchPreference: FetchPreference.envelope,
            );
          }
          hasMore = selected.messagesExists > page * _pageSize;
        }
        final previews = [
          for (final message in messages)
            if (message.uid != null && !message.isDeleted)
              _preview(selected, message),
        ]..sort((a, b) => b.id.uid.compareTo(a.id.uid));
        return (
          folders: folders,
          folder: selected.path,
          messages: previews,
          hasMore: hasMore,
        );
      });

  Future<MailDetails> readMessage(MailMessageId id) => _read((client) async {
    final folder = await _select(client, id);
    final message = await _message(client, id);
    final full = await client.fetchMessageContents(
      message,
      maxSize: 1024 * 1024,
      markAsSeen: true,
      includedInlineTypes: const [MediaToptype.text],
      responseTimeout: _responseTimeout,
    );
    return (
      preview: _preview(folder, full),
      recipients: full.to?.map((address) => address.email).join('、') ?? '',
      body: _plainText(full),
      replyTo: full.decodeSender().map((address) => address.email).join(', '),
      messageId: full.getHeaderValue('message-id'),
      attachments: _attachments(full),
    );
  });

  Future<void> markUnread(MailMessageId id) => _read((client) async {
    await _select(client, id);
    await client.markUnseen(_sequence(id));
  });

  Future<void> setStarred(MailMessageId id, bool value) =>
      _read((client) async {
        await _select(client, id);
        final sequence = _sequence(id);
        await (value
            ? client.markFlagged(sequence)
            : client.markUnflagged(sequence));
      });

  Future<void> move(MailMessageId id, String target) => _read((client) async {
    final folder = await _select(client, id);
    if (folder.path == target) return;
    final destination = client.mailboxes
        ?.where((mailbox) => mailbox.path == target && !mailbox.isNotSelectable)
        .firstOrNull;
    if (destination == null) throw const FormatException('邮箱文件夹已变更，请刷新');
    await client.moveMessages(_sequence(id), destination);
  });

  Future<bool> saveAttachment(
    MailMessageId id,
    MailAttachment attachment,
  ) async {
    final bytes = await _read((client) async {
      await _select(client, id);
      final message = await _message(client, id);
      final part = message.body?.getChildPart(attachment.id);
      final size = part?.size ?? attachment.bytes;
      if (size != null && size > _mailLimit) {
        throw const FormatException('此附件超过 15 MB，请通过网页版保存');
      }
      final downloaded = await client.fetchMessagePart(
        message,
        attachment.id,
        responseTimeout: _responseTimeout,
      );
      final bytes = downloaded.decodeContentBinary();
      if (bytes == null || bytes.length > _mailLimit) {
        throw const FormatException('无法保存此附件，请通过网页版下载');
      }
      return bytes;
    });
    return await pickerCache.run(
          () => FilePicker.saveFile(
            fileName: _fileName(attachment.name),
            bytes: bytes,
            dialogTitle: '保存邮件附件',
          ),
        ) !=
        null;
  }

  Future<bool> send({
    required String recipients,
    required String cc,
    required String bcc,
    required String subject,
    required String body,
    required List<PlatformFile> attachments,
    String? inReplyTo,
  }) async {
    final toAddresses = _recipients(recipients);
    final ccAddresses = _recipients(cc);
    final bccAddresses = _recipients(bcc);
    if (toAddresses.isEmpty) throw const FormatException('请输入收件人');
    final stored = await _stored();
    if (stored == null) throw StateError('请先连接校园邮箱');
    final builder = MessageBuilder()
      ..from = [MailAddress(null, stored.address)]
      ..to = toAddresses
      ..cc = ccAddresses
      ..bcc = bccAddresses
      ..subject = subject.trim()
      ..addTextPlain(body, transferEncoding: TransferEncoding.base64);
    if (inReplyTo != null && RegExp(r'^<[^<>\s]+>$').hasMatch(inReplyTo)) {
      builder.setHeader('In-Reply-To', inReplyTo);
      builder.setHeader('References', inReplyTo);
    }
    var total = 0;
    for (final file in attachments) {
      final path = file.path;
      if (path == null) throw const FormatException('无法读取附件');
      final size = await File(path).length();
      total += size;
      if (total > _mailLimit) throw const FormatException('附件合计不能超过 15 MB');
      final bytes = await File(path)
          .openRead(0, size)
          .fold<BytesBuilder>(
            BytesBuilder(),
            (data, chunk) => data..add(chunk),
          );
      builder.addBinary(
        bytes.takeBytes(),
        MediaSubtype.applicationOctetStream.mediaType,
        filename: _fileName(file.name),
      );
    }
    final message = builder.buildMimeMessage();
    return _open(stored, (client) async {
      await client.sendMessage(message, appendToSent: false);
      try {
        await client.listMailboxes();
        final sent = client.getMailbox(MailboxFlag.sent);
        if (sent == null) return false;
        // Keep the SMTP result even if IMAP cannot store the sent copy.
        message.bcc = null;
        message.removeHeader('Bcc');
        await client.appendMessage(message, sent, flags: [MessageFlags.seen]);
        return true;
      } catch (_) {
        return false;
      }
    });
  }

  Future<T> _read<T>(Future<T> Function(MailClient client) operation) async {
    final stored = await _stored();
    if (stored == null) throw StateError('请先连接校园邮箱');
    return _open(stored, operation);
  }

  Future<({String address, String code})?> _stored() async {
    final value = await _storage.read(key: _key);
    if (value == null) return null;
    final fields = jsonDecode(value) as List<dynamic>;
    final address = fields[0] as String;
    if (!_studentMailAddress.hasMatch(address)) return null;
    return (address: address, code: fields[1] as String);
  }

  Future<T> _open<T>(
    ({String address, String code}) credentials,
    Future<T> Function(MailClient client) operation,
  ) async {
    final client = MailClient(
      MailAccount.fromManualSettings(
        name: '东北大学本部学生邮箱',
        email: credentials.address,
        password: credentials.code,
        incomingHost: _mailServer,
        outgoingHost: _mailServer,
        outgoingClientDomain: 'mails.neu.edu.cn',
      ),
      clientId: const Id(name: 'NEUQ One'),
      defaultResponseTimeout: _responseTimeout,
    );
    try {
      await client.connect(timeout: _responseTimeout);
      return await operation(client);
    } finally {
      try {
        await client.disconnect();
      } catch (_) {
        // Keep the result of the mail operation.
      }
    }
  }
}

MailFolder _folder(Mailbox box) => (
  id: box.path,
  name: box.isInbox
      ? '收件箱'
      : box.isSent
      ? '已发送'
      : box.isDrafts
      ? '草稿箱'
      : box.isTrash
      ? '已删除'
      : box.isJunk
      ? '垃圾邮件'
      : box.name,
  inbox: box.isInbox,
  trash: box.isTrash,
);

MailPreview _preview(Mailbox folder, MimeMessage message) {
  final sender = message.from?.firstOrNull;
  return (
    id: (folder: folder.path, validity: folder.uidValidity!, uid: message.uid!),
    subject: message.decodeSubject()?.trim() ?? '',
    sender: sender?.personalName ?? sender?.email ?? '未知发件人',
    date: message.decodeDate(),
    seen: message.isSeen,
    starred: message.isFlagged,
  );
}

Future<Mailbox> _select(MailClient client, MailMessageId id) async {
  final folder = await client.selectMailboxByPath(id.folder);
  if (folder.uidValidity != id.validity) {
    throw const FormatException('邮箱内容已变更，请返回列表刷新');
  }
  return folder;
}

MessageSequence _sequence(MailMessageId id) =>
    MessageSequence.fromId(id.uid, isUid: true);

Future<MimeMessage> _message(MailClient client, MailMessageId id) async {
  final items = await client.fetchMessageSequence(
    _sequence(id),
    fetchPreference: FetchPreference.bodystructure,
  );
  final message = items.where((message) => message.uid == id.uid).firstOrNull;
  if (message == null) throw const FormatException('这封邮件已移动或删除');
  return message;
}

List<MailAttachment> _attachments(MimeMessage message) => [
  for (final item in message.findContentInfo())
    (
      id: item.fetchId,
      name: item.fileName ?? '附件 ${item.fetchId}',
      bytes: item.size,
    ),
];

String _plainText(MimeMessage message) {
  final plain = message.decodeTextPlainPart()?.trim();
  if (plain != null && plain.isNotEmpty) return plain;
  final rich = message.decodeTextHtmlPart();
  if (rich == null) return '';
  final document = html.parse(rich);
  for (final node in document.querySelectorAll('script, style, template')) {
    node.remove();
  }
  for (final block in document.querySelectorAll('br, p, div, li, tr')) {
    block.parentNode?.insertBefore(dom.Text('\n'), block);
  }
  return document.body?.text.trim() ?? '';
}

String _fileName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
  return cleaned.isEmpty || cleaned == '.' || cleaned == '..' ? '附件' : cleaned;
}

Future<List<PlatformFile>> pickMailAttachments() =>
    pickerCache.run(() => FilePicker.pickFiles(dialogTitle: '选择邮件附件'));

List<MailAddress> _recipients(String value) {
  if (value.trim().isEmpty) return [];
  final addresses = value
      .split(RegExp(r'[,，;；\s]+'))
      .where((item) => item.isNotEmpty);
  if (addresses.any(
    (address) => !RegExp(
      r'^[a-zA-Z0-9.!#$%&\x27*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+$',
    ).hasMatch(address),
  )) {
    throw const FormatException('请用逗号分隔有效的邮箱地址');
  }
  return addresses
      .toSet()
      .map((address) => MailAddress(null, address))
      .toList();
}
