import 'dart:convert';

import 'package:env_viewer/api/backend_client.dart';
import 'package:env_viewer/api/dto/environment_dto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('EnvironmentDto.fromJson', () {
    test('parses an environment with a fully-populated component', () {
      final dto = EnvironmentDto.fromJson({
        'id': 1,
        'name': 'Alpha',
        'memo': '主集成环境',
        'components': [
          {
            'id': 10,
            'role': 'GATEWAY',
            'version': '1.2.3',
            'versionUpdatedAt': '2026-06-20T08:30:00Z',
            'logLocation': '/var/log/gw.log',
            'listenPort': 8443,
            'protocol': 'https',
            'url': 'https://alpha.test/gw',
            'serverId': 100,
            'databaseIds': [200, 201],
            'versionProbe': 'HTTP',
            'collectionStatus': 'OK',
            'lastCollectedAt': '2026-06-26T01:00:00Z',
          },
        ],
      });

      expect(dto.id, 1);
      expect(dto.name, 'Alpha');
      expect(dto.memo, '主集成环境');
      expect(dto.components, hasLength(1));

      final c = dto.components.single;
      expect(c.id, 10);
      expect(c.role, 'GATEWAY');
      expect(c.version, '1.2.3');
      expect(c.versionUpdatedAt, DateTime.utc(2026, 6, 20, 8, 30));
      expect(c.logLocation, '/var/log/gw.log');
      expect(c.listenPort, 8443);
      expect(c.protocol, 'https');
      expect(c.url, 'https://alpha.test/gw');
      expect(c.serverId, 100);
      expect(c.databaseIds, [200, 201]);
      expect(c.versionProbe, 'HTTP');
      expect(c.collectionStatus, 'OK');
      expect(c.lastCollectedAt, DateTime.utc(2026, 6, 26, 1, 0));
    });

    test('tolerates nulls and missing collection fields (pre-slice-05)', () {
      final dto = EnvironmentDto.fromJson({
        'id': 2,
        'name': null,
        'memo': null,
        'components': [
          {
            'id': 11,
            'role': 'UI',
            'version': null,
            'versionUpdatedAt': null,
            'logLocation': null,
            'listenPort': null,
            'protocol': null,
            'url': null,
            'serverId': null,
            'databaseIds': [],
            'versionProbe': 'NONE',
            'collectionStatus': null,
            'lastCollectedAt': null,
          },
        ],
      });

      expect(dto.name, isNull);
      final c = dto.components.single;
      expect(c.version, isNull);
      expect(c.versionUpdatedAt, isNull);
      expect(c.serverId, isNull);
      expect(c.databaseIds, isEmpty);
      expect(c.collectionStatus, isNull);
    });

    test('defaults components to empty when the key is absent', () {
      final dto = EnvironmentDto.fromJson({'id': 3, 'name': 'Empty'});
      expect(dto.components, isEmpty);
    });
  });

  group('BackendClient', () {
    test('lists environments from /api/environments', () async {
      late Uri requested;
      final client = BackendClient(
        baseUrl: 'http://example.test:8080',
        httpClient: MockClient((req) async {
          requested = req.url;
          return http.Response(
            jsonEncode([
              {'id': 1, 'name': 'Alpha', 'memo': null, 'components': []},
              {'id': 2, 'name': 'Beta', 'memo': null, 'components': []},
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final envs = await client.listEnvironments();

      expect(requested.toString(), 'http://example.test:8080/api/environments');
      expect(envs.map((e) => e.name), ['Alpha', 'Beta']);
    });

    test('fetches a single environment by id', () async {
      final client = BackendClient(
        baseUrl: 'http://example.test:8080/',
        httpClient: MockClient((req) async {
          expect(req.url.path, '/api/environments/7');
          return http.Response(
            jsonEncode({'id': 7, 'name': 'Gamma', 'components': []}),
            200,
          );
        }),
      );

      final env = await client.getEnvironment(7);
      expect(env.id, 7);
      expect(env.name, 'Gamma');
    });

    test('throws a localized BackendException on a non-2xx response', () async {
      final client = BackendClient(
        baseUrl: 'http://example.test:8080',
        httpClient: MockClient((req) async => http.Response('boom', 500)),
      );

      expect(
        () => client.listEnvironments(),
        throwsA(
          isA<BackendException>().having(
            (e) => e.message,
            'message',
            contains('500'),
          ),
        ),
      );
    });

    test('trailing slash in baseUrl does not double up the path', () async {
      late Uri requested;
      final client = BackendClient(
        baseUrl: 'http://example.test:8080/',
        httpClient: MockClient((req) async {
          requested = req.url;
          return http.Response('[]', 200);
        }),
      );

      await client.listEnvironments();
      expect(requested.toString(), 'http://example.test:8080/api/environments');
    });
  });
}
