import 'dart:convert';

import '../../../core/auth/neuq_login_protocol.dart';

const campusCardHost = 'cardmobile.neuq.edu.cn';
final campusCardEntry = Uri.https(campusCardHost, '/home/toHomePage');

bool _secureSchoolUrl(Uri uri) =>
    uri.scheme == 'https' && uri.port == 443 && uri.userInfo.isEmpty;

bool isCampusCardPage(Uri uri) =>
    _secureSchoolUrl(uri) && uri.host == campusCardHost;

bool campusCardNavigationAllowed(Uri uri) {
  if (isCampusCardPage(uri)) return true;
  if (!_secureSchoolUrl(uri) ||
      uri.host != schoolIdentityHost ||
      !uri.path.startsWith('/authserver/')) {
    return false;
  }
  try {
    final recipients = uri.queryParametersAll['service'];
    if (recipients == null) return true;
    if (recipients.length != 1) return false;
    final recipient = Uri.tryParse(recipients.single);
    return recipient != null &&
        isCampusCardPage(recipient) &&
        recipient.path == campusCardEntry.path;
  } on FormatException {
    return false;
  }
}

enum CampusCardReadFailure implements Exception {
  accountMismatch,
  unreadable,
  signInRequired,
}

/// Only a balance shown with a single identifiable owner on the official site
/// can be associated with the app's current school account.
int readCampusCardBalance(Uri document, Object result, String subject) {
  if (!isCampusCardPage(document) || result is! String) {
    throw CampusCardReadFailure.unreadable;
  }
  try {
    final raw = jsonDecode(result);
    final fields = raw is String ? jsonDecode(raw) : raw;
    if (fields is! Map ||
        fields['origin'] != 'https://$campusCardHost' ||
        fields['studentCode'] is! String ||
        fields['cents'] is! int) {
      throw CampusCardReadFailure.unreadable;
    }
    final owner = schoolSubjectForStudentCode(fields['studentCode'] as String);
    if (owner == null) throw CampusCardReadFailure.unreadable;
    if (owner != subject) throw CampusCardReadFailure.accountMismatch;
    final cents = fields['cents'] as int;
    if (!validCampusCardCents(cents)) throw CampusCardReadFailure.unreadable;
    return cents;
  } on FormatException {
    throw CampusCardReadFailure.unreadable;
  }
}

bool validCampusCardCents(int cents) => cents.abs() <= 99999999;

const campusCardBalanceProbe = r'''
(() => {
  const origin = "https://cardmobile.neuq.edu.cn";
  if (location.origin !== origin || !document.body) return "{}";
  const visibility = new WeakMap();
  const visible = node => {
    if (!node) return true;
    if (!visibility.has(node)) {
      const style = getComputedStyle(node);
      visibility.set(node, visible(node.parentElement) &&
        node.getAttribute("aria-hidden") !== "true" &&
        style.visibility === "visible" && style.opacity !== "0" &&
        style.contentVisibility !== "hidden" &&
        (node.getClientRects().length > 0 || style.display === "contents"));
    }
    return visibility.get(node);
  };
  if ([...document.querySelectorAll('input[type="password"]')].some(visible)) return "{}";

  const texts = new WeakMap();
  const normalize = value => value.normalize("NFKC").replace(/[\u200B-\u200D\uFEFF]/g, "")
    .replace(/\s+/g, " ").trim();
  const text = node => {
    if (!texts.has(node)) {
      const parts = [];
      if (visible(node) && !node.matches("script,style,template,noscript,svg,input,textarea,select")) {
        for (const part of node.childNodes) {
          if (part.nodeType === Node.TEXT_NODE && getComputedStyle(node).webkitTextSecurity === "none") {
            parts.push(part.textContent);
          } else if (part.nodeType === Node.ELEMENT_NODE) {
            parts.push(text(part));
          }
        }
      }
      texts.set(node, normalize(parts.join(" ")));
    }
    return texts.get(node);
  };
  const codeLabel = /^(?:学工号|学号|工号)\s*:?$/;
  const embeddedCode = /^(?:学工号|学号|工号)\s*:?\s*([0-9]{7,20})$/;
  const account = /^\p{L}[\p{L}\p{M} ·・.'’\-]{0,30}\s*(?:\(\s*)?([0-9]{7,20})(?:\s*\))?$/u;
  const amountLabel = /^(?:(?:校园卡|账户|卡内|可用)\s*)?余\s*额\s*(?:\(\s*元\s*\))?\s*:?\s*/;
  const money = /^([−-])?\s*(¥)?\s*([0-9]{1,3}(?:\s*,\s*[0-9]{3})+|[0-9]{1,6})(?:\s*\.\s*([0-9]{1,2}))?(?!\d|\s*[.,]\s*\d)\s*(元)?/;
  const centsIn = value => {
    const match = money.exec(value);
    if (!match) return null;
    const tail = value.slice(match[0].length).trim();
    if (tail && !match[2] && !match[5]) return null;
    const cents = Number(match[3].replace(/[\s,]/g, "")) * 100 +
      Number((match[4] ?? "").padEnd(2, "0"));
    return match[1] ? -cents : cents;
  };
  const studentCodes = new Set();
  const namedAccounts = [];
  const balances = [];

  for (const node of document.body.querySelectorAll("*")) {
    const label = text(node);
    if (!label) continue;
    const next = node.nextElementSibling;
    const adjacent = () => next ? text(next) : "";
    const code = embeddedCode.exec(label)?.[1] ??
      (codeLabel.test(label) && /^[0-9]{7,20}$/.test(adjacent()) ? adjacent() : null);
    if (code) studentCodes.add(code);
    const named = account.exec(label);
    if (named) namedAccounts.push({node, code: named[1]});
    const prefix = amountLabel.exec(label);
    if (!prefix) continue;
    const cents = centsIn(label.slice(prefix[0].length) || adjacent());
    if (cents !== null) balances.push({node, cents});
  }

  // Some generations of the card page show name and student number together
  // on the same virtual card surface as the labelled balance.
  if (studentCodes.size === 0) {
    for (const balance of balances) {
      let container = balance.node;
      for (; container && container !== document.body; container = container.parentElement) {
        const accountCodes = namedAccounts.filter(item => container.contains(item.node));
        if (!accountCodes.length) continue;
        for (const item of accountCodes) studentCodes.add(item.code);
        break;
      }
    }
  }
  const amounts = new Set(balances.map(balance => balance.cents));
  return JSON.stringify({
    origin,
    studentCode: studentCodes.size === 1 ? [...studentCodes][0] : null,
    cents: amounts.size === 1 ? [...amounts][0] : null
  });
})()
''';
