import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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

  test('school searches upgrade known pages and keep sign-in interactive', () {
    final form = Uri.http(
      schoolAcademicHost,
      '/eams/classroom/apply/free.action',
    );
    expect(academicReadAddress(form), form.replace(scheme: 'https', port: 443));
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
      final data = {
        'origin': 'https://jwxt.neuq.edu.cn',
        'signedIn': true,
        'studentCode': '00001234',
      };
      final json = jsonEncode(data);
      final subject = schoolSubjectFromEvidence(schoolWebEntry, json);
      expect(subject, isNotNull);
      expect(isStoredSchoolSubject(subject!), isTrue);
      expect(subject, isNot(contains(data['studentCode'])));
      expect(
        schoolSubjectFromEvidence(schoolWebEntry, jsonEncode(json)),
        subject,
      );
      expect(schoolSubjectFromEvidence(schoolAcademicLogin, json), isNull);
      expect(
        schoolSubjectFromEvidence(
          Uri.https(schoolIdentityHost, '/authserver/login'),
          json,
        ),
        isNull,
      );
      expect(
        schoolSubjectFromEvidence(
          schoolWebEntry,
          jsonEncode({...data, 'origin': 'https://other.example'}),
        ),
        isNull,
      );
      expect(
        schoolSubjectFromEvidence(
          schoolWebEntry,
          jsonEncode({...data, 'signedIn': false}),
        ),
        isNull,
      );
      expect(
        schoolSubjectFromEvidence(
          schoolWebEntry,
          jsonEncode({...data, 'studentCode': null}),
        ),
        isNull,
      );
      expect(schoolSubjectFromEvidence(schoolWebEntry, 'invalid'), isNull);
    },
  );
}
