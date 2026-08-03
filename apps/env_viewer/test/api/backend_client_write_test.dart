import 'dart:convert';

import 'package:env_viewer/api/backend_client.dart';
import 'package:env_viewer/api/dto/component_input.dart';
import 'package:env_viewer/api/dto/environment_input.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('ComponentInput.toJson', () {
    test('carries the wire enum codes and scalar fields verbatim', () {
      final json = const ComponentInput(
        role: 'GATEWAY',
        version: '1.0',
        logLocation: '/var/log/x.log',
        listenPort: 8080,
        protocol: 'https',
        url: 'https://x/health',
        versionProbe: 'HTTP',
      ).toJson();

      expect(json['role'], 'GATEWAY');
      expect(json['version'], '1.0');
      expect(json['logLocation'], '/var/log/x.log');
      expect(json['listenPort'], 8080);
      expect(json['protocol'], 'https');
      expect(json['url'], 'https://x/health');
      expect(json['versionProbe'], 'HTTP');
    });

    test('emits versionUpdatedAt as a UTC ISO-8601 instant', () {
      final json = ComponentInput(
        role: 'APP',
        versionUpdatedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
      ).toJson();

      expect(json['versionUpdatedAt'], '2026-01-02T03:04:05.000Z');
    });

    test('leaves optional fields null rather than dropping their keys', () {
      final json = const ComponentInput(role: 'UI').toJson();
      expect(json.containsKey('version'), isTrue);
      expect(json['version'], isNull);
      expect(json['versionUpdatedAt'], isNull);
      expect(json['versionProbe'], isNull);
    });
  });

  group('EnvironmentInput.toJson', () {
    test('nests inline component inputs', () {
      final json = const EnvironmentInput(
        name: 'ENV-A',
        memo: 'memo',
        components: [ComponentInput(role: 'APP')],
      ).toJson();

      expect(json['name'], 'ENV-A');
      expect(json['memo'], 'memo');
      expect((json['components'] as List).single['role'], 'APP');
    });
  });

  group('BackendClient writes', () {
    test('createEnvironment POSTs the input and parses the result', () async {
      late http.Request captured;
      final client = BackendClient(
        baseUrl: 'http://test',
        httpClient: MockClient((req) async {
          captured = req;
          return http.Response(
            jsonEncode({'id': 7, 'name': 'ENV-A', 'components': []}),
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final dto = await client.createEnvironment(
        const EnvironmentInput(name: 'ENV-A'),
      );

      expect(captured.method, 'POST');
      expect(captured.url.path, '/api/environments');
      expect(jsonDecode(captured.body)['name'], 'ENV-A');
      expect(dto.id, 7);
    });

    test('updateEnvironment PUTs to the id path', () async {
      late http.Request captured;
      final client = BackendClient(
        baseUrl: 'http://test',
        httpClient: MockClient((req) async {
          captured = req;
          return http.Response(
            jsonEncode({'id': 7, 'name': 'NEW', 'components': []}),
            200,
          );
        }),
      );

      final dto = await client.updateEnvironment(
        7,
        const EnvironmentInput(name: 'NEW'),
      );

      expect(captured.method, 'PUT');
      expect(captured.url.path, '/api/environments/7');
      expect(dto.name, 'NEW');
    });

    test('deleteEnvironment DELETEs and tolerates a 204 empty body', () async {
      late http.Request captured;
      final client = BackendClient(
        baseUrl: 'http://test',
        httpClient: MockClient((req) async {
          captured = req;
          return http.Response('', 204);
        }),
      );

      await client.deleteEnvironment(7);

      expect(captured.method, 'DELETE');
      expect(captured.url.path, '/api/environments/7');
    });

    test('addComponent POSTs to the nested components path', () async {
      late http.Request captured;
      final client = BackendClient(
        baseUrl: 'http://test',
        httpClient: MockClient((req) async {
          captured = req;
          return http.Response(jsonEncode({'id': 11, 'role': 'UI'}), 201);
        }),
      );

      final dto = await client.addComponent(7, const ComponentInput(role: 'UI'));

      expect(captured.method, 'POST');
      expect(captured.url.path, '/api/environments/7/components');
      expect(jsonDecode(captured.body)['role'], 'UI');
      expect(dto.role, 'UI');
    });

    test('updateComponent PUTs to the nested component id path', () async {
      late http.Request captured;
      final client = BackendClient(
        baseUrl: 'http://test',
        httpClient: MockClient((req) async {
          captured = req;
          return http.Response(jsonEncode({'id': 11, 'role': 'GATEWAY'}), 200);
        }),
      );

      final dto = await client.updateComponent(
        7,
        11,
        const ComponentInput(role: 'GATEWAY'),
      );

      expect(captured.url.path, '/api/environments/7/components/11');
      expect(dto.role, 'GATEWAY');
    });

    test('deleteComponent DELETEs the nested path', () async {
      late http.Request captured;
      final client = BackendClient(
        baseUrl: 'http://test',
        httpClient: MockClient((req) async {
          captured = req;
          return http.Response('', 204);
        }),
      );

      await client.deleteComponent(7, 11);

      expect(captured.method, 'DELETE');
      expect(captured.url.path, '/api/environments/7/components/11');
    });

    test('surfaces a localized BackendException on a non-2xx write', () async {
      final client = BackendClient(
        baseUrl: 'http://test',
        httpClient: MockClient((_) async => http.Response('bad', 400)),
      );

      expect(
        () => client.createEnvironment(const EnvironmentInput(name: 'X')),
        throwsA(
          isA<BackendException>().having(
            (e) => e.message,
            'message',
            contains('400'),
          ),
        ),
      );
    });

    test('surfaces the backend problem+json detail in the error', () async {
      final client = BackendClient(
        baseUrl: 'http://test',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'title': 'Resource not found',
              'detail': 'Environment not found: 9',
              'status': 404,
            }),
            404,
            headers: {'content-type': 'application/problem+json'},
          ),
        ),
      );

      expect(
        () => client.deleteEnvironment(9),
        throwsA(
          isA<BackendException>().having(
            (e) => e.message,
            'message',
            contains('Environment not found: 9'),
          ),
        ),
      );
    });
  });
}
