import 'dart:async';
import 'dart:convert';

import 'package:env_viewer/api/backend_client.dart';
import 'package:env_viewer/catalog/environment_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 立即采集 (issue 08): the store triggers server-side Collection for one
/// Environment and swaps the returned fresh view in place — no full re-fetch,
/// no impact on sibling Environments, transient errors surfaced to the caller
/// rather than parked in [EnvironmentStore.error].
void main() {
  const listJson = [
    {
      'id': 1,
      'name': 'Alpha',
      'memo': null,
      'components': [
        {'id': 10, 'role': 'APP', 'version': '1.0.0'},
      ],
    },
    {'id': 2, 'name': 'Beta', 'memo': null, 'components': []},
  ];

  const freshAlphaJson = {
    'id': 1,
    'name': 'Alpha',
    'memo': null,
    'components': [
      {
        'id': 10,
        'role': 'APP',
        'version': '2.0.0',
        'versionUpdatedAt': '2026-07-01T02:30:00Z',
        'collectionStatus': 'OK',
        'lastCollectedAt': '2026-07-07T01:00:00Z',
      },
    ],
  };

  test('collectNow POSTs to the refresh endpoint and swaps the env in place',
      () async {
    final requests = <String>[];
    final store = EnvironmentStore(
      BackendClient(
        baseUrl: 'http://test',
        httpClient: MockClient((req) async {
          requests.add('${req.method} ${req.url.path}');
          if (req.method == 'POST' && req.url.path == '/api/environments/1/refresh') {
            return http.Response(jsonEncode(freshAlphaJson), 200);
          }
          if (req.url.path == '/api/environments') {
            return http.Response(jsonEncode(listJson), 200);
          }
          return http.Response('[]', 200); // servers/databases refs
        }),
      ),
    );
    await store.load();

    final error = await store.collectNow(1);

    expect(error, isNull);
    expect(requests, contains('POST /api/environments/1/refresh'));
    // Swapped in place from the response — not re-fetched.
    expect(requests.where((r) => r == 'GET /api/environments'), hasLength(1));
    final alpha = store.environments.singleWhere((e) => e.id == 1);
    expect(alpha.components.single.version, '2.0.0');
    expect(
      alpha.components.single.versionUpdatedAt,
      DateTime.utc(2026, 7, 1, 2, 30),
    );
    // Sibling untouched, ordering preserved.
    expect(store.environments.map((e) => e.id), [1, 2]);
  });

  test('reports in-flight state while the request runs', () async {
    final gate = Completer<void>();
    final store = EnvironmentStore(
      BackendClient(
        baseUrl: 'http://test',
        httpClient: MockClient((req) async {
          if (req.method == 'POST') {
            await gate.future;
            return http.Response(jsonEncode(freshAlphaJson), 200);
          }
          return http.Response(
            jsonEncode(req.url.path == '/api/environments' ? listJson : []),
            200,
          );
        }),
      ),
    );
    await store.load();

    final pending = store.collectNow(1);
    expect(store.isCollecting(1), isTrue);
    expect(store.isCollecting(2), isFalse);

    gate.complete();
    await pending;
    expect(store.isCollecting(1), isFalse);
  });

  test('returns the localized error and leaves store.error untouched', () async {
    final store = EnvironmentStore(
      BackendClient(
        baseUrl: 'http://test',
        httpClient: MockClient((req) async {
          if (req.method == 'POST') {
            return http.Response(
              jsonEncode({
                'title': 'Bad Gateway',
                'detail': '采集失败：无法连接业务库',
              }),
              502,
            );
          }
          return http.Response(
            jsonEncode(req.url.path == '/api/environments' ? listJson : []),
            200,
          );
        }),
      ),
    );
    await store.load();

    final error = await store.collectNow(1);

    expect(error, contains('502'));
    expect(store.error, isNull);
    expect(store.isCollecting(1), isFalse);
    // The known-good view stays as it was.
    final alpha = store.environments.singleWhere((e) => e.id == 1);
    expect(alpha.components.single.version, '1.0.0');
  });
}
