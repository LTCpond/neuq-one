import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuq_one/features/mail/data/campus_mail.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final repository = CampusMailRepository(const FlutterSecureStorage(), 'test');

  for (final domain in ['stu.neuq.edu.cn', 'neuq.edu.cn', 'qhd.neu.edu.cn']) {
    test('retired mailbox domain $domain cannot connect or restore', () async {
      final address = 'student@$domain';
      FlutterSecureStorage.setMockInitialValues({
        'campusMailbox:test': jsonEncode([address, 'example-code']),
      });

      expect(await repository.address(), isNull);
      await expectLater(
        repository.connect(address, ''),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('本部学生邮箱地址'),
          ),
        ),
      );
    });
  }

  for (final domain in ['mails.neu.edu.cn', 'stu.neu.edu.cn']) {
    test('main campus mailbox domain $domain restores', () async {
      final address = 'student@$domain';
      FlutterSecureStorage.setMockInitialValues({
        'campusMailbox:test': jsonEncode([address, 'example-code']),
      });

      expect(await repository.address(), address);
    });
  }
}
