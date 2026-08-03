import 'dart:convert';

import 'package:env_viewer/api/backend_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('BackendClient credential brokering', () {
    test('fetches an SSH credential bundle for a server', () async {
      late Uri requested;
      final client = BackendClient(
        baseUrl: 'http://example.test:8080',
        httpClient: MockClient((req) async {
          requested = req.url;
          return http.Response(
            jsonEncode({
              'serverId': 5,
              'host': '10.0.0.1',
              'port': 22,
              'username': 'deploy',
              'secret': 's3cr3t',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final cred = await client.getServerCredentials(5);

      expect(requested.path, '/api/servers/5/credentials');
      expect(cred.serverId, 5);
      expect(cred.host, '10.0.0.1');
      expect(cred.port, 22);
      expect(cred.username, 'deploy');
      expect(cred.secret, 's3cr3t');
    });

    test('fetches a DB credential bundle with a jdbc url', () async {
      final client = BackendClient(
        baseUrl: 'http://example.test:8080',
        httpClient: MockClient((req) async {
          expect(req.url.path, '/api/databases/9/credentials');
          return http.Response(
            jsonEncode({
              'databaseId': 9,
              'type': 'ORACLE',
              'host': '10.0.2.5',
              'port': 1521,
              'serviceName': 'ORCL',
              'username': 'app',
              'jdbcUrl': 'jdbc:oracle:thin:@//10.0.2.5:1521/ORCL',
              'secret': 'db-pw',
            }),
            200,
          );
        }),
      );

      final cred = await client.getDatabaseCredentials(9);

      expect(cred.databaseId, 9);
      expect(cred.type, 'ORACLE');
      expect(cred.serviceName, 'ORCL');
      expect(cred.jdbcUrl, 'jdbc:oracle:thin:@//10.0.2.5:1521/ORCL');
      expect(cred.secret, 'db-pw');
    });

    test('tolerates an absent secret (none stored)', () async {
      final client = BackendClient(
        baseUrl: 'http://example.test:8080',
        httpClient: MockClient((req) async {
          return http.Response(
            jsonEncode({
              'serverId': 1,
              'host': '10.0.0.1',
              'port': 22,
              'username': 'deploy',
            }),
            200,
          );
        }),
      );

      final cred = await client.getServerCredentials(1);
      expect(cred.secret, isNull);
      expect(cred.username, 'deploy');
    });

    test('surfaces a 404 as a localized BackendException', () async {
      final client = BackendClient(
        baseUrl: 'http://example.test:8080',
        httpClient: MockClient((req) async => http.Response('not found', 404)),
      );

      expect(
        () => client.getDatabaseCredentials(123),
        throwsA(
          isA<BackendException>().having(
            (e) => e.message,
            'message',
            contains('404'),
          ),
        ),
      );
    });
  });
}
