import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:neuq_one/core/auth/neuq_login_protocol.dart';

void main() {
  test('silent reauthentication follows only a valid school CAS login', () {
    final client = Uri(
      scheme: 'http',
      host: schoolIdentityHost,
      path: '/authserver/login',
      queryParameters: {
        'service':
            'http://$schoolAcademicHost/eams/homeExt.action;jsessionid=ABC',
      },
    );
    expect(academicSessionAddress(client)?.scheme, 'https');
    expect(academicSessionAddress(client)?.query, client.query);
    expect(academicReadAddress(client), isNull);
    expect(
      academicSessionAddress(client.replace(path: '/authserver/logout')),
      isNull,
    );
    expect(
      academicSessionAddress(
        client.replace(
          queryParameters: {
            'service': 'https://other.example/eams/homeExt.action',
          },
        ),
      ),
      isNull,
    );
  });

  test('academic reads keep sign-in interactive', () {
    expect(academicReadAddress(schoolWebEntry), schoolWebEntry);
    expect(academicReadAddress(schoolAcademicLogin), isNull);
    expect(
      academicReadAddress(Uri.https(schoolIdentityHost, '/authserver/login')),
      isNull,
    );
    expect(
      academicReadAddress(Uri.http(schoolAcademicHost, '/eams/unknown.action')),
      isNull,
    );
  });

  test('web login stays on the two school HTTPS origins', () {
    expect(schoolNavigation(schoolWebEntry), SchoolNavigation.allow);
    expect(schoolNavigation(schoolAcademicLogin), SchoolNavigation.allow);
    expect(
      schoolNavigation(Uri.parse('https://ids.neuq.edu.cn/authserver/login')),
      SchoolNavigation.allow,
    );
    for (final url in [
      'https://ids.neuq.edu.cn.other.example/authserver/login',
      'https://ids.neuq.edu.cn:8443/authserver/login',
      'https://jwxt.neuq.edu.cn/elsewhere',
      'https://account@jwxt.neuq.edu.cn/eams/',
      'http://jwxt.neuq.edu.cn/eams/localLogin.action',
      'file:///eams/',
      'https://ids.neuq.edu.cn/authserver/login?service=https://outside.example/',
      'https://ids.neuq.edu.cn/authserver/login?service=https://jwxt.neuq.edu.cn/eams/home.action&service=https://jwxt.neuq.edu.cn/eams/homeExt.action',
    ]) {
      expect(
        schoolNavigation(Uri.parse(url)),
        SchoolNavigation.block,
        reason: url,
      );
    }
  });

  test(
    'known school redirects upgrade transport while preserving encoded service',
    () {
      const service =
          'http://jwxt.neuq.edu.cn/eams/homeExt.action;jsessionid=EXAMPLE';
      final redirect = Uri.http(schoolIdentityHost, '/authserver/login', {
        'service': service,
      });
      expect(schoolNavigation(redirect), SchoolNavigation.upgrade);
      final safe = redirect.replace(scheme: 'https', port: 443);
      expect(schoolNavigation(safe), SchoolNavigation.allow);
      expect(safe.queryParameters['service'], service);

      final successRedirect = Uri.http(
        schoolAcademicHost,
        '/eams/homeExt.action;jsessionid=EXAMPLE',
        {'ticket': 'example-only'},
      );
      expect(schoolNavigation(successRedirect), SchoolNavigation.upgrade);
      expect(
        successRedirect
            .replace(scheme: 'https', port: 443)
            .queryParameters['ticket'],
        'example-only',
      );
    },
  );

  test(
    'session requires school origin, authenticated controls and student code',
    () {
      const account =
          '<h1>教务管理系统</h1><a href="/eams/account.action">示例同学（00001234）</a>';
      const logout = '<a href="/eams/logout.action">退出</a>';
      final valid = html.parse('$account$logout');
      final subject = schoolSubjectFromDocument(schoolWebEntry, valid);
      expect(subject, schoolSubjectForStudentCode('00001234'));
      expect(isStoredSchoolSubject(subject!), isTrue);
      expect(subject, isNot(contains('00001234')));
      expect(schoolSubjectFromDocument(schoolAcademicLogin, valid), isNull);
      expect(
        schoolSubjectFromDocument(Uri.https('other.example'), valid),
        isNull,
      );
      for (final body in [
        account,
        logout,
        '$logout<div hidden>$account</div>',
        '$account$logout<input type="password">',
        '$account$logout<a href="/eams/account.action">其他同学(00005678)</a>',
      ]) {
        expect(
          schoolSubjectFromDocument(schoolWebEntry, html.parse(body)),
          isNull,
          reason: body,
        );
      }
    },
  );
}
