import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuq_one/core/auth/neuq_login_protocol.dart';
import 'package:neuq_one/features/services/data/campus_card_balance.dart';
import 'package:neuq_one/features/services/data/campus_card_payment.dart';
import 'package:neuq_one/features/services/data/campus_card_protocol.dart';

void main() {
  test(
    'a campus card ticket must return to the exact requested HTTPS service',
    () {
      final service = campusCardEntry.replace(
        queryParameters: {'source': 'app'},
      );
      final login = Uri.https(schoolIdentityHost, '/authserver/login', {
        'service': service.toString(),
      });
      expect(campusCardCasService(login), service);
      expect(
        campusCardCasService(
          login.replace(
            queryParameters: {...login.queryParameters, 'renew': 'true'},
          ),
        ),
        isNull,
      );
      final valid = service.replace(
        queryParameters: {'ticket': 'ST-example', 'source': 'app'},
      );
      expect(isCampusCardCasReturn(service, valid), isTrue);
      for (final invalid in [
        valid.replace(host: 'example.org'),
        valid.replace(path: '/home/other'),
        valid.replace(
          queryParameters: {
            'ticket': ['one', 'two'],
            'source': 'app',
          },
        ),
        valid.replace(
          queryParameters: {'ticket': 'ST-example', 'source': 'altered'},
        ),
        valid.replace(queryParameters: {'ticket': 'ST-example'}),
        service,
      ]) {
        expect(isCampusCardCasReturn(service, invalid), isFalse);
      }
    },
  );

  test('the campus card browser accepts the verified HTTPS portal and its CAS return service', () {
    expect(campusCardNavigationAllowed(campusCardEntry), isTrue);
    expect(
      campusCardNavigationAllowed(
        Uri.https(schoolIdentityHost, '/authserver/login', {
          'service': campusCardEntry.toString(),
        }),
      ),
      isTrue,
    );
    for (final value in [
      'http://cardmobile.neuq.edu.cn/home/toHomePage',
      'https://cardmobile.neuq.edu.cn.example.org/home/toHomePage',
      'https://x@cardmobile.neuq.edu.cn/home/toHomePage',
      'https://cardmobile.neuq.edu.cn:8443/home/toHomePage',
      'https://ids.neuq.edu.cn/authserver/login?service=https://example.org/card',
      'https://ids.neuq.edu.cn/authserver/login?service=https://cardmobile.neuq.edu.cn/other',
    ]) {
      expect(
        campusCardNavigationAllowed(Uri.parse(value)),
        isFalse,
        reason: value,
      );
    }
  });

  test(
    'official cashiers can open from the campus card or the same wallet',
    () {
      final wechat = Uri.parse(
        'https://wx.tenpay.com/cgi-bin/mmpayweb-bin/checkmweb?order=sample',
      );
      final alipay = Uri.parse('https://mclient.alipay.com/cashier/sample');
      expect(campusCardCashier(wechat), CampusCardWallet.wechat);
      expect(campusCardCashier(alipay), CampusCardWallet.alipay);
      expect(
        campusCardPaymentAllowedFrom(campusCardEntry, CampusCardWallet.wechat),
        isTrue,
      );
      expect(
        campusCardPaymentAllowedFrom(alipay, CampusCardWallet.alipay),
        isTrue,
      );
      expect(
        campusCardPaymentAllowedFrom(alipay, CampusCardWallet.wechat),
        isFalse,
      );
      expect(
        campusCardPaymentAllowedFrom(schoolWebEntry, CampusCardWallet.wechat),
        isFalse,
      );
      expect(
        campusCardPaymentAllowedFrom(null, CampusCardWallet.wechat),
        isFalse,
      );
      expect(campusCardNavigationAllowed(wechat), isFalse);
      expect(campusCardNavigationAllowed(alipay), isFalse);
      for (final value in [
        'https://wx.tenpay.com.example.org/cgi-bin/mmpayweb-bin/checkmweb',
        'https://example.org@wx.tenpay.com/cgi-bin/mmpayweb-bin/checkmweb',
        'https://wx.tenpay.com:8443/cgi-bin/mmpayweb-bin/checkmweb',
        'http://mclient.alipay.com/cashier/sample',
      ]) {
        expect(campusCardCashier(Uri.parse(value)), isNull, reason: value);
      }
    },
  );

  test('wallet links preserve order data and discard Android intent extras', () {
    final wechat = Uri.parse('weixin://wap/pay?prepayid%3Dsample&sign=A%2BB');
    final alipay = Uri.parse('alipays://platformapi/startApp?orderStr=A%2BC');
    expect(campusCardWalletLink(wechat), (
      wallet: CampusCardWallet.wechat,
      uri: wechat,
    ));
    expect(campusCardWalletLink(alipay), (
      wallet: CampusCardWallet.alipay,
      uri: alipay,
    ));
    expect(
      campusCardWalletLink(
        Uri.parse(
          'intent://platformapi/startApp?orderStr=A%2BC'
          '#Intent;scheme=alipays;package=com.eg.android.AlipayGphone;'
          'S.browser_fallback_url=https%3A%2F%2Fexample.org;end',
        ),
      ),
      (wallet: CampusCardWallet.alipay, uri: alipay),
    );
    for (final value in [
      'weixin://wap/pay',
      'weixin://dl/scan?value=sample',
      'weixin://wap:123/pay?order=sample',
      'alipays://platformapi.example.org/startapp?order=sample',
      'alipays://user@platformapi/startapp?order=sample',
      'intent://wap/pay?order=sample#Intent;scheme=weixin;package=example;end',
      'intent://wap/pay?order=sample#Intent;scheme=weixin;scheme=alipays;end',
      'intent://wap/pay?order=sample#Intent;scheme=;end',
      'intent://wap/pay?order=sample#Intent;scheme=weixin',
      'intent://wap/pay?order=sample#Intent;scheme=javascript;end',
    ]) {
      expect(campusCardWalletLink(Uri.parse(value)), isNull, reason: value);
    }
  });

  test('balance evidence is accepted only for the signed-in owner at the card origin', () {
    const code = '00001234';
    final expected = schoolSubjectForStudentCode(code)!;
    final evidence = {
      'origin': 'https://cardmobile.neuq.edu.cn',
      'studentCode': code,
      'cents': 0,
    };
    final data = jsonEncode(evidence);
    expect(readCampusCardBalance(campusCardEntry, data, expected), 0);
    expect(
      readCampusCardBalance(campusCardEntry, jsonEncode(data), expected),
      0,
    );
    expect(campusCardMoney(1705), '¥17.05');
    expect(campusCardMoney(-50), '−¥0.50');
    expect(
      () => readCampusCardBalance(
        campusCardEntry,
        data,
        schoolSubjectForStudentCode('00009999')!,
      ),
      throwsA(CampusCardReadFailure.accountMismatch),
    );
    expect(
      () => readCampusCardBalance(schoolWebEntry, data, expected),
      throwsA(CampusCardReadFailure.unreadable),
    );
    for (final invalid in [
      {'cents': null},
      {'cents': 99.5},
      {'studentCode': null},
      {'origin': 'https://example.org'},
    ]) {
      expect(
        () => readCampusCardBalance(
          campusCardEntry,
          jsonEncode({...evidence, ...invalid}),
          expected,
        ),
        throwsA(CampusCardReadFailure.unreadable),
      );
    }
  });
}
