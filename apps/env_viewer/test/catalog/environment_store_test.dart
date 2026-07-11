import 'dart:convert';

import 'package:env_viewer/api/backend_client.dart';
import 'package:env_viewer/catalog/environment_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

BackendClient _clientReturning(Object json) {
  return BackendClient(
    baseUrl: 'http://test',
    httpClient: MockClient((_) async => _jsonResponse(json)),
  );
}

http.Response _jsonResponse(Object? body, [int statusCode = 200]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      statusCode,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  group('EnvironmentStore.load', () {
    test('loads, remaps, and marks itself connected', () async {
      final store = EnvironmentStore(
        _clientReturning([
          {'id': 1, 'name': 'Alpha', 'memo': null, 'components': []},
          {'id': 2, 'name': 'Beta', 'memo': null, 'components': []},
        ]),
      );

      await store.load();

      expect(store.connected, isTrue);
      expect(store.error, isNull);
      expect(store.totalCount, 2);
      expect(store.environments.map((e) => e.name), ['Alpha', 'Beta']);
    });

    test('captures a localized error instead of throwing', () async {
      final store = EnvironmentStore(
        BackendClient(
          baseUrl: 'http://test',
          httpClient: MockClient((_) async => http.Response('nope', 503)),
        ),
      );

      await store.load();

      expect(store.error, contains('503'));
      expect(store.connected, isFalse);
      expect(store.environments, isEmpty);
    });
  });

  group('EnvironmentStore.setSearch', () {
    test('filters by name, memo, and component fields', () async {
      final store = EnvironmentStore(
        _clientReturning([
          {
            'id': 1,
            'name': 'Alpha',
            'memo': '主集成环境',
            'components': [
              {'id': 10, 'role': 'GATEWAY', 'version': '1.2.3'},
            ],
          },
          {
            'id': 2,
            'name': 'Beta',
            'memo': null,
            'components': [
              {'id': 11, 'role': 'UI', 'version': '9.9.9'},
            ],
          },
        ]),
      );
      await store.load();

      store.setSearch('alpha');
      expect(store.environments.map((e) => e.id), [1]);

      store.setSearch('集成');
      expect(store.environments.map((e) => e.id), [1]);

      store.setSearch('9.9.9');
      expect(store.environments.map((e) => e.id), [2]);

      store.setSearch('网关'); // localized role label is searchable
      expect(store.environments.map((e) => e.id), [1]);

      store.setSearch('');
      expect(store.environments, hasLength(2));
    });

    test('notifies listeners only when the query actually changes', () async {
      final store = EnvironmentStore(_clientReturning([]));
      await store.load();

      var notifications = 0;
      store.addListener(() => notifications++);

      store.setSearch('x');
      store.setSearch('x'); // no-op
      expect(notifications, 1);
    });
  });
}
