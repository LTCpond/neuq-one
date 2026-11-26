import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuq_one/core/network/public_data_client.dart';
import 'package:neuq_one/features/services/data/school_policies.dart';

void main() {
  final pdf = utf8.encode('%PDF-1.7\n%%EOF');
  final updatedPdf = utf8.encode('%PDF-2.0\n%%EOF');
  late Directory directory;

  String catalog(List<int> bytes, {String id = 'grade-point'}) => jsonEncode({
    'version': 1,
    'policies': [
      {
        'id': id,
        'title': '东北大学秦皇岛分校本科生学分绩点实施办法',
        'category': '学业成绩',
        'sha256': sha256.convert(bytes).toString(),
      },
    ],
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('school-policies-');
  });

  tearDown(() => directory.delete(recursive: true));

  SchoolPolicyRepository repository(MockClientHandler handler) {
    final client = MockClient(handler);
    addTearDown(client.close);
    return SchoolPolicyRepository(
      PublicDataClient(client),
      () async => directory,
    );
  }

  test('catalog and PDF remain readable after the public host fails', () async {
    final online = repository((request) async {
      expect(request.url.origin, publicAssetsRoot.origin);
      return switch (request.url.path) {
        '/assets/policies/index.json' => http.Response(
          catalog(pdf),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
        '/assets/policies/grade-point.pdf' => http.Response.bytes(pdf, 200),
        _ => throw StateError('Unexpected resource ${request.url.path}'),
      };
    });
    final policy = (await online.loadCatalog().single).single;
    expect(await online.loadPdf(policy), pdf);

    var requests = 0;
    final offline = repository((_) async {
      requests++;
      return http.Response('', 503);
    });
    final savedPolicy = (await offline.loadCatalog().single).single;
    expect(savedPolicy.title, policy.title);
    expect(await offline.loadPdf(savedPolicy), pdf);
    expect(requests, 1);
  });

  test(
    'invalid catalog and mismatched PDF cannot replace cached data',
    () async {
      var index = catalog(pdf);
      var file = pdf;
      final repositoryUnderTest = repository((request) async {
        return request.url.path.endsWith('index.json')
            ? http.Response(
                index,
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              )
            : http.Response.bytes(file, 200);
      });
      final original = (await repositoryUnderTest.loadCatalog().single).single;
      await repositoryUnderTest.loadPdf(original);

      index = catalog(pdf, id: '../grade-point');
      expect(
        (await repositoryUnderTest.loadCatalog().single).single.id,
        original.id,
      );

      index = catalog(updatedPdf);
      final updated = (await repositoryUnderTest.loadCatalog().last).single;
      await expectLater(
        repositoryUnderTest.loadPdf(updated),
        throwsFormatException,
      );
      expect(await repositoryUnderTest.loadPdf(original), pdf);

      file = updatedPdf;
      expect(await repositoryUnderTest.loadPdf(updated), updatedPdf);
    },
  );
}
