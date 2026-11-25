import 'dart:convert';

import 'package:uuid/uuid.dart';

const schoolIdentityHost = 'ids.neuq.edu.cn';
const schoolAcademicHost = 'jwxt.neuq.edu.cn';
final schoolWebEntry = Uri.https(schoolAcademicHost, '/eams/homeExt.action');
final schoolAcademicLogin = Uri.https(
  schoolAcademicHost,
  '/eams/localLogin.action',
);

enum SchoolNavigation { allow, upgrade, block }

SchoolNavigation schoolNavigation(Uri uri) {
  if (uri.userInfo.isNotEmpty) {
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
  // These are the school's observed document redirects. Upgrade the browser
  // navigation itself without modifying the CAS service or ticket parameters.
  final upgrade = uri.host == schoolIdentityHost
      ? path == '/authserver/login'
      : const {
          '/eams',
          '/eams/',
          '/eams/home.action',
          '/eams/homeExt.action',
          '/eams/classroom/apply/free.action',
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

/// Returns only a pseudonymous identifier for the account whose information
/// and authenticated controls were read from the official academic document.
String? schoolSubjectFromEvidence(Uri document, Object value) {
  if (!isAcademicDocument(document) || value is! String) return null;
  try {
    final decoded = jsonDecode(value);
    final evidence = decoded is String ? jsonDecode(decoded) : decoded;
    if (evidence is! Map ||
        evidence['origin'] != 'https://$schoolAcademicHost' ||
        evidence['signedIn'] != true ||
        evidence['studentCode'] is! String) {
      return null;
    }
    return schoolSubjectForStudentCode(evidence['studentCode'] as String);
  } on FormatException {
    return null;
  }
}

String? schoolSubjectForStudentCode(String code) {
  if (!RegExp(r'^[0-9]{7,20}$').hasMatch(code)) return null;
  return 'neuq-eams:${const Uuid().v5(Namespace.url.value, 'https://$schoolAcademicHost/student/$code')}';
}

bool isStoredSchoolSubject(String value) => RegExp(
  r'^neuq-eams:[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
).hasMatch(value);

/// Evaluated only on a first-party academic page. Read identifiers from
/// rendered student fields and the authenticated portal's account link.
const schoolIdentityProbe = r'''
(() => {
  const origin = "https://jwxt.neuq.edu.cn";
  if (location.origin !== origin) return "{}";

  const documents = [document];
  for (let i = 0; i < documents.length && documents.length < 10; i++) {
    for (const frame of documents[i].querySelectorAll("frame, iframe")) {
      if (documents.length >= 10) break;
      try {
        const page = frame.contentDocument;
        if (page && page.location.origin === origin && !documents.includes(page)) {
          documents.push(page);
        }
      } catch (_) {}
    }
  }

  const visible = node => node.getClientRects().length > 0 &&
    node.ownerDocument.defaultView.getComputedStyle(node).visibility === "visible";
  const text = node => (node.textContent || "").trim().replace(/\s+/g, " ");
  const studentLabel = /^(?:学生学号|学号|student(?:id|number))$/i;
  const studentCode = /^[0-9]{7,20}$/;
  const logoutLabel = /^(?:退出(?:登录|系统)?|注销|sign out|log out)$/i;
  const portalTitle = /^(?:教务管理系统|教务系统)$/;
  const accountLabel = /^\p{L}[\p{L}\p{M} ·・.'’\u002d]{0,39}[（(]([0-9]{7,20})[）)]$/u;
  const fieldName = value => value.replace(/\s+/g, "");
  const ids = new Set();
  let signedIn = false;

  for (const page of documents) {
    if (/login|logout/i.test(page.location.pathname) ||
        page.querySelector('input[type="password"]')) continue;

    const controls = [...page.querySelectorAll("a, button")].filter(visible);
    const hasLogout = controls.some(link => {
      if (logoutLabel.test(text(link))) return true;
      if (!link.href) return false;
      try {
        const target = new URL(link.href);
        return target.origin === origin &&
          /^\/eams\/logout\.action(?:;jsessionid=[\w.-]+)?$/i.test(target.pathname);
      } catch (_) {
        return false;
      }
    });
    if (hasLogout) signedIn = true;

    const labels = [...page.querySelectorAll(
      "th, td, dt, label, span, div, p, b, strong, legend, h1, h2, h3, h4, h5, h6"
    )].filter(visible);
    const labelTexts = new Set(labels.map(node => fieldName(text(node))));
    const isProfile = hasLogout && labelTexts.has("基本信息") &&
      labelTexts.has("角色信息") && labelTexts.has("学生");
    const isPortal = hasLogout && (portalTitle.test(fieldName(page.title)) ||
      controls.some(node => portalTitle.test(fieldName(text(node)))) ||
      [...labelTexts].some(value => portalTitle.test(value)));

    if (isPortal) {
      for (const link of controls) {
        if (link.tagName !== "A") continue;
        const account = accountLabel.exec(text(link));
        if (account) ids.add(account[1]);
      }
    }

    for (const label of labels) {
      if (label.childElementCount > 2) continue;
      const field = /^([^：:]+?)(?:[：:](.*))?$/.exec(fieldName(text(label)));
      if (!field || !(studentLabel.test(field[1]) ||
        (isProfile && field[1] === "名称"))) continue;

      const candidate = label.nextElementSibling;
      const value = field[2] ||
        (candidate && visible(candidate) ? text(candidate) : "");
      if (studentCode.test(value)) {
        ids.add(value);
      }
    }
  }

  return JSON.stringify({
    origin,
    signedIn,
    studentCode: ids.size === 1 ? [...ids][0] : null
  });
})()
''';
