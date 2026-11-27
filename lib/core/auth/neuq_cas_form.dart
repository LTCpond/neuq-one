import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:pointycastle/export.dart';

import 'neuq_login_protocol.dart';

enum SchoolCasChallenge { captcha, device, additional }

SchoolCasChallenge? schoolCasChallenge(Document page) {
  bool visible(String selector) => page
      .querySelectorAll(selector)
      .any(
        (element) =>
            element.attributes['type'] != 'hidden' &&
            schoolElementVisible(element),
      );

  final text = _visibleText(page);
  if (RegExp(r'设备校验|设备验证|验证设备').hasMatch(text)) {
    return SchoolCasChallenge.device;
  }
  if (page.querySelector(
            'input[name="needCaptcha"][value="true"], input[name="needCaptcha"][value="1"]',
          ) !=
          null ||
      visible(
        'input[name="captcha"], input[name="captchaResponse"], input[name="captchaCode"], #captchaImg, [data-sitekey]',
      ) ||
      RegExp(r'请输入验证码|验证码错误|需要验证码|请完成验证码|滑块验证|请拖动滑块|请拖动下方滑块').hasMatch(text)) {
    return SchoolCasChallenge.captcha;
  }
  if (visible(
        'input[name="otp"], input[name="smsCode"], input[autocomplete="one-time-code"]',
      ) ||
      RegExp(r'请完成验证|双重登录认证|二次认证|多因素认证').hasMatch(text)) {
    return SchoolCasChallenge.additional;
  }
  return null;
}

final _passwordRejection = RegExp(
  r'密码\s*(?:(?:输入|填写)\s*)?(?:不正确|不匹配|错误|有误)'
  r'(?!\s*(?:次数|过多|超过|[0-9０-９一二三四五六七八九十]+\s*次))'
  r'|(?:无效的?\s*(?:凭据|凭证|认证信息)|(?:凭据|凭证|认证信息)\s*(?:无效|错误|有误))'
  r'|\b(?:invalid\s+(?:credentials|username\s+or\s+password)|incorrect\s+password)\b',
  caseSensitive: false,
);

bool schoolCasPasswordRejected(Document page) =>
    _passwordRejection.hasMatch(_visibleText(page));

String _visibleText(Document page) {
  final body = page.body;
  if (body == null || !schoolElementVisible(body)) return '';

  Iterable<String> parts(Node parent) sync* {
    for (final node in parent.nodes) {
      if (node is Text) {
        yield node.data;
      } else if (node is Element &&
          !const {'script', 'style'}.contains(node.localName) &&
          schoolElementVisible(node)) {
        yield* parts(node);
      }
    }
  }

  return parts(body).join(' ');
}

class SchoolCasPasswordForm {
  SchoolCasPasswordForm._(this.action, this._salt, this._fields);

  final String action;
  final List<int> _salt;
  final Map<String, String> _fields;

  static SchoolCasPasswordForm? parse(Document page) {
    final forms = page.querySelectorAll('form#casLoginForm');
    if (forms.length != 1) return null;
    final form = forms.single;
    final action = form.attributes['action'];
    if (action == null ||
        action.trim().isEmpty ||
        form.attributes['method']?.toLowerCase() != 'post') {
      return null;
    }

    String? field(String name) =>
        form.querySelector('input[name="$name"]')?.attributes['value'];
    final salt = utf8.encode(
      form.querySelector('#pwdDefaultEncryptSalt')?.attributes['value'] ?? '',
    );
    final lt = field('lt');
    final execution = field('execution');
    if (salt.length != 16 ||
        lt == null ||
        lt.isEmpty ||
        execution == null ||
        execution.isEmpty ||
        form.querySelector('[name="username"]') == null ||
        form.querySelector('[name="password"]') == null) {
      return null;
    }

    return SchoolCasPasswordForm._(action, salt, {
      'lt': lt,
      'execution': execution,
      '_eventId': field('_eventId') ?? 'submit',
      'dllt': field('dllt') ?? 'userNamePasswordLogin',
      'rmShown': field('rmShown') ?? '1',
    });
  }

  Map<String, String> fields(String username, String password) => {
    ..._fields,
    'username': username,
    'password': _encodePassword(password, _salt),
  };
}

String _encodePassword(String password, List<int> salt) {
  // This is the CAS form's wire format. HTTPS protects the complete form.
  const alphabet = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';
  final random = Random.secure();
  int randomCharacter(int _) =>
      alphabet.codeUnitAt(random.nextInt(alphabet.length));
  final iv = Uint8List.fromList(List.generate(16, randomCharacter));
  final prefix = List.generate(64, randomCharacter);
  final bytes = Uint8List.fromList([...prefix, ...utf8.encode(password)]);
  try {
    final cipher =
        PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
          ..init(
            true,
            PaddedBlockCipherParameters(
              ParametersWithIV(KeyParameter(Uint8List.fromList(salt)), iv),
              null,
            ),
          );
    return base64.encode(cipher.process(bytes));
  } finally {
    bytes.fillRange(0, bytes.length, 0);
  }
}
