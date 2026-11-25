import 'package:html/dom.dart';

import 'package:uuid/uuid.dart';

const schoolIdentityHost = 'ids.neuq.edu.cn';
const schoolAcademicHost = 'jwxt.neuq.edu.cn';
const campusCardHost = 'cardmobile.neuq.edu.cn';
final campusCardEntry = Uri.https(campusCardHost, '/home/toHomePage');
final schoolWebEntry = Uri.https(schoolAcademicHost, '/eams/homeExt.action');
final schoolAcademicLogin = Uri.https(
  schoolAcademicHost,
  '/eams/localLogin.action',
);

enum SchoolNavigation { allow, upgrade, block }

SchoolNavigation schoolNavigation(Uri uri) {
  if (uri.userInfo.isNotEmpty || uri.hasFragment) {
    return SchoolNavigation.block;
  }
  final path = _path(uri);
  if (uri.host == schoolIdentityHost) {
    if (!path.startsWith('/authserver/')) return SchoolNavigation.block;
    if (!_validService(uri)) return SchoolNavigation.block;
  } else if (uri.host == schoolAcademicHost) {
    if (path != '/eams' && !path.startsWith('/eams/')) {
      return SchoolNavigation.block;
    }
  } else {
    return SchoolNavigation.block;
  }

  if (uri.scheme == 'https' && uri.port == 443) {
    return SchoolNavigation.allow;
  }
  // Keep the school-issued CAS parameters when upgrading document redirects.
  final upgrade = uri.host == schoolIdentityHost
      ? path == '/authserver/login'
      : const {
          '/eams',
          '/eams/',
          '/eams/home.action',
          '/eams/homeExt.action',
        }.contains(path);
  return upgrade && uri.scheme == 'http' && uri.port == 80
      ? SchoolNavigation.upgrade
      : SchoolNavigation.block;
}

bool _validService(Uri uri) {
  try {
    final values = uri.queryParametersAll['service'];
    if (values == null) return true;
    if (values.length != 1) return false;
    final target = Uri.tryParse(values.single);
    return target != null &&
        target.userInfo.isEmpty &&
        !target.hasFragment &&
        target.host == schoolAcademicHost &&
        (target.scheme == 'https' && target.port == 443 ||
            target.scheme == 'http' && target.port == 80) &&
        const {
          '/eams/home.action',
          '/eams/homeExt.action',
        }.contains(_path(target));
  } on FormatException {
    return false;
  }
}

String _path(Uri uri) => uri.path.replaceAll(
  RegExp(r';jsessionid=[A-Za-z0-9._-]+(?=/|$)', caseSensitive: false),
  '',
);

bool isAcademicDocument(Uri uri) {
  final path = _path(uri).toLowerCase();
  return schoolNavigation(uri) == SchoolNavigation.allow &&
      uri.host == schoolAcademicHost &&
      !path.contains('login') &&
      !path.contains('logout');
}

Uri? academicReadAddress(Uri uri) {
  if (isAcademicDocument(uri)) return uri;
  if (uri.host == schoolAcademicHost &&
      schoolNavigation(uri) == SchoolNavigation.upgrade) {
    return uri.replace(scheme: 'https', port: 443);
  }
  return null;
}

bool isAcademicCasLogin(Uri uri) =>
    uri.host == schoolIdentityHost &&
    _path(uri) == '/authserver/login' &&
    schoolNavigation(uri) != SchoolNavigation.block;

Uri? academicSessionAddress(Uri uri) {
  if (!isAcademicCasLogin(uri)) return academicReadAddress(uri);
  return schoolNavigation(uri) == SchoolNavigation.upgrade
      ? uri.replace(scheme: 'https', port: 443)
      : uri;
}

Uri? campusCardCasService(Uri login) {
  if (login.scheme != 'https' ||
      login.host != schoolIdentityHost ||
      login.port != 443 ||
      login.userInfo.isNotEmpty ||
      login.hasFragment ||
      _path(login) != '/authserver/login') {
    return null;
  }
  try {
    final parameters = login.queryParametersAll;
    if (parameters.containsKey('renew')) return null;
    final values = parameters['service'];
    final service = values?.length == 1 ? Uri.tryParse(values!.single) : null;
    if (service == null ||
        service.originOrNull != campusCardEntry.origin ||
        service.path != campusCardEntry.path ||
        service.userInfo.isNotEmpty ||
        service.hasFragment ||
        service.queryParametersAll.containsKey('ticket')) {
      return null;
    }
    return service;
  } on FormatException {
    return null;
  }
}

bool isCampusCardCasReturn(Uri service, Uri callback) {
  if (callback.originOrNull != campusCardEntry.origin ||
      callback.originOrNull != service.originOrNull ||
      callback.path != campusCardEntry.path ||
      callback.path != service.path ||
      callback.userInfo.isNotEmpty ||
      callback.hasFragment) {
    return false;
  }
  try {
    final expected = service.queryParametersAll;
    final actual = callback.queryParametersAll;
    final tickets = actual['ticket'];
    if (tickets?.length != 1 ||
        !RegExp(r'^[!-~]{1,512}$').hasMatch(tickets!.single) ||
        actual.length != expected.length + 1) {
      return false;
    }
    return expected.entries.every((entry) {
      final values = actual[entry.key];
      return values != null &&
          values.length == entry.value.length &&
          values.indexed.every((item) => item.$2 == entry.value[item.$1]);
    });
  } on FormatException {
    return false;
  }
}

String? schoolSubjectForStudentCode(String code) {
  if (!RegExp(r'^[0-9]{7,20}$').hasMatch(code)) return null;
  return 'neuq-eams:${const Uuid().v5(Namespace.url.value, 'https://$schoolAcademicHost/student/$code')}';
}

bool isStoredSchoolSubject(String value) => RegExp(
  r'^neuq-eams:[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
).hasMatch(value);

final _accountLabel = RegExp(
  r"^\p{L}[\p{L}\p{M} ·・.'’\-]{0,39}[（(]([0-9]{7,20})[）)]$",
  unicode: true,
);
final _studentField = RegExp(
  r'^(学生学号|学号|studentid|studentnumber|名称)(?:[：:](.*))?$',
  caseSensitive: false,
);

bool schoolElementVisible(Element element) {
  for (Element? node = element; node != null; node = node.parent) {
    final style = (node.attributes['style'] ?? '').toLowerCase().replaceAll(
      RegExp(r'\s'),
      '',
    );
    if (node.localName == 'template' ||
        node.attributes.containsKey('hidden') ||
        node.attributes['aria-hidden'] == 'true' ||
        node.classes.any(const {'hide', 'hidden', 'd-none'}.contains) ||
        style.contains('display:none') ||
        style.contains('visibility:hidden')) {
      return false;
    }
  }
  return true;
}

String? schoolSubjectFromDocument(Uri address, Document page) {
  if (!isAcademicDocument(address) ||
      page.querySelector('input[type="password"]') != null) {
    return null;
  }
  final controls = page
      .querySelectorAll('a, button')
      .where(schoolElementVisible);
  final signedIn = controls.any((element) {
    final href = element.attributes['href'];
    final link = href == null
        ? null
        : address.resolveUri(Uri.tryParse(href) ?? Uri());
    return (link != null &&
            link.originOrNull == address.origin &&
            _path(link) == '/eams/logout.action') ||
        const {
          '退出',
          '退出登录',
          '退出系统',
          '注销',
          'sign out',
          'log out',
        }.contains(element.text.trim().toLowerCase());
  });
  if (!signedIn) return null;

  final labels = page
      .querySelectorAll(
        'th, td, dt, label, span, div, p, h1, h2, h3, h4, h5, h6, b, strong',
      )
      .where(schoolElementVisible);
  String compact(Element node) => node.text.replaceAll(RegExp(r'\s'), '');
  final texts = labels.map(compact).toSet();
  const titles = {'教务管理系统', '教务系统'};
  final portal =
      titles.any(texts.contains) ||
      titles.contains(page.querySelector('title')?.text.trim()) ||
      controls.any((element) => titles.contains(compact(element)));
  final profile = const {'基本信息', '角色信息', '学生'}.every(texts.contains);
  final subjects = <String>{};

  void addCode(String? code) {
    final subject = code == null
        ? null
        : schoolSubjectForStudentCode(code.trim());
    if (subject != null) subjects.add(subject);
  }

  if (portal) {
    for (final link in controls.where((element) => element.localName == 'a')) {
      addCode(_accountLabel.firstMatch(link.text.trim())?.group(1));
    }
  }
  for (final label in labels) {
    if (label.children.length > 2) continue;
    final field = _studentField.firstMatch(compact(label));
    if (field == null || field.group(1) == '名称' && !profile) continue;
    final sibling = label.nextElementSibling;
    final value = field.group(2);
    addCode(
      value != null && value.isNotEmpty
          ? value
          : sibling != null && schoolElementVisible(sibling)
          ? sibling.text
          : null,
    );
  }
  return subjects.length == 1 ? subjects.single : null;
}

extension on Uri {
  String? get originOrNull =>
      hasAuthority && (scheme == 'https' || scheme == 'http') ? origin : null;
}
