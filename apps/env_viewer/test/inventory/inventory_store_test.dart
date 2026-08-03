import 'dart:async';
import 'dart:convert';

import 'package:env_viewer/api/backend_client.dart';
import 'package:env_viewer/api/dto/database_input.dart';
import 'package:env_viewer/api/dto/server_input.dart';
import 'package:env_viewer/inventory/inventory_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _jsonResponse(Object? body, [int statusCode = 200]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      statusCode,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  group('InventoryStore.load', () {
    test(
      'loads both canonical inventories into localized stable views',
      () async {
        final store = InventoryStore(
          BackendClient(
            baseUrl: 'http://test',
            httpClient: MockClient((request) async {
              if (request.url.path == '/api/servers') {
                return _jsonResponse([
                  {'id': 2, 'host': 'node-b', 'os': 'WINDOWS'},
                  {
                    'id': 1,
                    'host': 'node-a',
                    'os': 'LINUX',
                    'ssh': {'host': 'ssh-a', 'port': 22, 'username': 'ops'},
                  },
                ]);
              }
              if (request.url.path == '/api/databases') {
                return _jsonResponse([
                  {
                    'id': 12,
                    'role': 'intermediate',
                    'type': 'OCEANBASE',
                    'connection': {'host': 'db-b', 'port': 2881},
                  },
                  {
                    'id': 11,
                    'role': 'business',
                    'type': 'ORACLE',
                    'connection': {'host': 'db-a', 'port': 1521},
                  },
                ]);
              }
              return _jsonResponse({'title': 'not found'}, 404);
            }),
          ),
        );

        await store.load();

        expect(store.loaded, isTrue);
        expect(store.loading, isFalse);
        expect(store.error, isNull);
        expect(store.servers.map((view) => view.id), [1, 2]);
        expect(store.servers.first.osLabel, 'Linux');
        expect(store.databases.map((view) => view.id), [11, 12]);
        expect(store.databases.first.roleLabel, '业务库');
        expect(store.serversById[1]?.sshAddress, 'ops@ssh-a');
        expect(store.databasesById[12]?.typeLabel, 'OceanBase');
      },
    );

    test(
      'a failed reload keeps the last good inventory and exposes its reason',
      () async {
        var failReload = false;
        final store = InventoryStore(
          BackendClient(
            baseUrl: 'http://test',
            httpClient: MockClient((request) async {
              if (request.url.path == '/api/servers') {
                return failReload
                    ? _jsonResponse({'detail': '库存暂不可用'}, 503)
                    : _jsonResponse([
                        {'id': 1, 'host': 'keep-server', 'os': 'LINUX'},
                      ]);
              }
              if (request.url.path == '/api/databases') {
                return _jsonResponse([
                  {'id': 2, 'role': 'business', 'type': 'ORACLE'},
                ]);
              }
              return _jsonResponse({'title': 'not found'}, 404);
            }),
          ),
        );
        await store.load();

        failReload = true;
        await store.load();

        expect(store.loaded, isTrue);
        expect(store.servers.single.displayLabel, 'keep-server');
        expect(store.databases.single.id, 2);
        expect(store.error, '库存暂不可用（503）');
      },
    );

    test(
      'reports loading while both inventory requests are in flight',
      () async {
        final serverResponse = Completer<http.Response>();
        final databaseResponse = Completer<http.Response>();
        final store = InventoryStore(
          BackendClient(
            baseUrl: 'http://test',
            httpClient: MockClient((request) {
              return request.url.path == '/api/servers'
                  ? serverResponse.future
                  : databaseResponse.future;
            }),
          ),
        );

        final load = store.load();
        await Future<void>.delayed(Duration.zero);
        expect(store.loading, isTrue);

        serverResponse.complete(_jsonResponse([]));
        databaseResponse.complete(_jsonResponse([]));
        await load;
        expect(store.loading, isFalse);
      },
    );
  });

  group('InventoryStore Server mutations', () {
    test('a successful create reloads the canonical inventory', () async {
      var serverLoads = 0;
      final store = InventoryStore(
        BackendClient(
          baseUrl: 'http://test',
          httpClient: MockClient((request) async {
            if (request.method == 'POST' &&
                request.url.path == '/api/servers') {
              return _jsonResponse({
                'id': 2,
                'host': 'request-value',
                'os': 'LINUX',
              }, 201);
            }
            if (request.url.path == '/api/servers') {
              serverLoads++;
              return _jsonResponse(
                serverLoads == 1
                    ? [
                        {'id': 1, 'host': 'node-a', 'os': 'LINUX'},
                      ]
                    : [
                        {'id': 2, 'host': 'canonical-node', 'os': 'LINUX'},
                      ],
              );
            }
            if (request.url.path == '/api/databases') {
              return _jsonResponse([]);
            }
            return _jsonResponse({'title': 'not found'}, 404);
          }),
        ),
      );
      await store.load();

      final succeeded = await store.createServer(
        const ServerInput(host: 'request-value', os: 'LINUX'),
      );

      expect(succeeded, isTrue);
      expect(serverLoads, 2);
      expect(store.servers.single.displayLabel, 'canonical-node');
      expect(store.error, isNull);
    });

    test(
      'a failed delete preserves data and surfaces the backend reason',
      () async {
        final store = InventoryStore(
          BackendClient(
            baseUrl: 'http://test',
            httpClient: MockClient((request) async {
              if (request.method == 'DELETE') {
                return _jsonResponse({'detail': '服务器仍被环境使用'}, 409);
              }
              if (request.url.path == '/api/servers') {
                return _jsonResponse([
                  {'id': 4, 'host': 'keep-me', 'os': 'LINUX'},
                ]);
              }
              if (request.url.path == '/api/databases') {
                return _jsonResponse([]);
              }
              return _jsonResponse({'title': 'not found'}, 404);
            }),
          ),
        );
        await store.load();

        final succeeded = await store.deleteServer(4);

        expect(succeeded, isFalse);
        expect(store.servers.single.id, 4);
        expect(store.error, '服务器仍被环境使用（409）');
      },
    );

    test('a successful update reloads the edited Server', () async {
      var updated = false;
      final store = InventoryStore(
        BackendClient(
          baseUrl: 'http://test',
          httpClient: MockClient((request) async {
            if (request.method == 'PUT') {
              updated = true;
              return _jsonResponse({
                'id': 4,
                'host': 'request-value',
                'os': 'WINDOWS',
              });
            }
            if (request.url.path == '/api/servers') {
              return _jsonResponse([
                {
                  'id': 4,
                  'host': updated ? 'canonical-windows' : 'node-a',
                  'os': updated ? 'WINDOWS' : 'LINUX',
                },
              ]);
            }
            if (request.url.path == '/api/databases') {
              return _jsonResponse([]);
            }
            return _jsonResponse({'title': 'not found'}, 404);
          }),
        ),
      );
      await store.load();

      final succeeded = await store.updateServer(
        4,
        const ServerInput(host: 'request-value', os: 'WINDOWS'),
      );

      expect(succeeded, isTrue);
      expect(store.servers.single.displayLabel, 'canonical-windows');
      expect(store.servers.single.osLabel, 'Windows');
    });
  });

  group('InventoryStore Database mutations', () {
    test('a successful create reloads the canonical inventory', () async {
      var databaseLoads = 0;
      final store = InventoryStore(
        BackendClient(
          baseUrl: 'http://test',
          httpClient: MockClient((request) async {
            if (request.method == 'POST' &&
                request.url.path == '/api/databases') {
              return _jsonResponse({
                'id': 6,
                'role': 'business',
                'type': 'ORACLE',
              }, 201);
            }
            if (request.url.path == '/api/servers') {
              return _jsonResponse([]);
            }
            if (request.url.path == '/api/databases') {
              databaseLoads++;
              return _jsonResponse(
                databaseLoads == 1
                    ? []
                    : [
                        {
                          'id': 6,
                          'role': 'business',
                          'type': 'ORACLE',
                          'connection': {'host': 'canonical-db'},
                        },
                      ],
              );
            }
            return _jsonResponse({'title': 'not found'}, 404);
          }),
        ),
      );
      await store.load();

      final succeeded = await store.createDatabase(
        const DatabaseInput(
          role: 'business',
          type: 'ORACLE',
          connection: DatabaseConnectionInput(host: 'request-db'),
        ),
      );

      expect(succeeded, isTrue);
      expect(databaseLoads, 2);
      expect(store.databases.single.host, 'canonical-db');
    });

    test('a successful update reloads the edited Database', () async {
      var updated = false;
      final store = InventoryStore(
        BackendClient(
          baseUrl: 'http://test',
          httpClient: MockClient((request) async {
            if (request.method == 'PUT') {
              updated = true;
              return _jsonResponse({
                'id': 6,
                'role': 'intermediate',
                'type': 'DAMENG',
              });
            }
            if (request.url.path == '/api/servers') {
              return _jsonResponse([]);
            }
            if (request.url.path == '/api/databases') {
              return _jsonResponse([
                {
                  'id': 6,
                  'role': updated ? 'intermediate' : 'business',
                  'type': updated ? 'DAMENG' : 'ORACLE',
                },
              ]);
            }
            return _jsonResponse({'title': 'not found'}, 404);
          }),
        ),
      );
      await store.load();

      final succeeded = await store.updateDatabase(
        6,
        const DatabaseInput(role: 'intermediate', type: 'DAMENG'),
      );

      expect(succeeded, isTrue);
      expect(store.databases.single.roleLabel, '中转库');
      expect(store.databases.single.typeLabel, '达梦');
    });

    test('a successful delete reloads without the removed Database', () async {
      var deleted = false;
      final store = InventoryStore(
        BackendClient(
          baseUrl: 'http://test',
          httpClient: MockClient((request) async {
            if (request.method == 'DELETE') {
              deleted = true;
              return http.Response('', 204);
            }
            if (request.url.path == '/api/servers') {
              return _jsonResponse([]);
            }
            if (request.url.path == '/api/databases') {
              return _jsonResponse(
                deleted
                    ? []
                    : [
                        {'id': 6, 'role': 'business', 'type': 'ORACLE'},
                      ],
              );
            }
            return _jsonResponse({'title': 'not found'}, 404);
          }),
        ),
      );
      await store.load();

      final succeeded = await store.deleteDatabase(6);

      expect(succeeded, isTrue);
      expect(store.databases, isEmpty);
    });
  });

  group('InventoryStore reverse lookups', () {
    test('maps Environments that run on a Server into catalog views', () async {
      final store = InventoryStore(
        BackendClient(
          baseUrl: 'http://test',
          httpClient: MockClient((request) async {
            expect(request.url.path, '/api/servers/7/environments');
            return _jsonResponse([
              {
                'id': 3,
                'name': 'ENV-A',
                'components': [
                  {'id': 31, 'role': 'APP', 'serverId': 7},
                ],
              },
            ]);
          }),
        ),
      );

      final environments = await store.environmentsOnServer(7);

      expect(environments.single.name, 'ENV-A');
      expect(environments.single.components.single.roleLabel, '主服务');
    });

    test('maps Environments that use a Database into catalog views', () async {
      final store = InventoryStore(
        BackendClient(
          baseUrl: 'http://test',
          httpClient: MockClient((request) async {
            expect(request.url.path, '/api/databases/9/environments');
            return _jsonResponse([
              {
                'id': 4,
                'name': 'ENV-B',
                'components': [
                  {
                    'id': 41,
                    'role': 'GATEWAY',
                    'databaseIds': [9],
                  },
                ],
              },
            ]);
          }),
        ),
      );

      final environments = await store.environmentsUsingDatabase(9);

      expect(environments.single.name, 'ENV-B');
      expect(environments.single.components.single.roleLabel, '网关');
    });
  });

  group('InventoryStore search', () {
    InventoryStore storeWith() => InventoryStore(
      BackendClient(
        baseUrl: 'http://test',
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/servers') {
            return _jsonResponse([
              {
                'id': 1,
                'host': 'app01.internal',
                'os': 'LINUX',
                'ssh': {'host': 'gw.internal', 'port': 22, 'username': 'ops'},
              },
              {'id': 2, 'host': 'win01', 'os': 'WINDOWS'},
            ]);
          }
          if (request.url.path == '/api/databases') {
            return _jsonResponse([
              {
                'id': 11,
                'role': 'business',
                'type': 'ORACLE',
                'connection': {'host': 'db-a', 'username': 'app_user'},
              },
              {
                'id': 12,
                'role': 'intermediate',
                'type': 'DAMENG',
                'connection': {'host': 'db-b'},
              },
            ]);
          }
          return _jsonResponse({'title': 'not found'}, 404);
        }),
      ),
    );

    test('filters servers across id/host/os/ssh, case-insensitively', () async {
      final store = storeWith();
      await store.load();

      store.setSearch('APP01');
      expect(store.filteredServers.map((s) => s.id), [1]);

      store.setSearch('windows');
      expect(store.filteredServers.map((s) => s.id), [2]);

      store.setSearch('ops@gw');
      expect(store.filteredServers.map((s) => s.id), [1]);

      store.setSearch('nothing-matches');
      expect(store.filteredServers, isEmpty);
    });

    test('filters databases across role/type/address/username', () async {
      final store = storeWith();
      await store.load();

      store.setSearch('中转');
      expect(store.filteredDatabases.map((d) => d.id), [12]);

      store.setSearch('oracle');
      expect(store.filteredDatabases.map((d) => d.id), [11]);

      store.setSearch('app_user');
      expect(store.filteredDatabases.map((d) => d.id), [11]);
    });

    test('one query filters both inventories; blank restores all', () async {
      final store = storeWith();
      await store.load();

      store.setSearch('db-a');
      expect(store.filteredServers, isEmpty);
      expect(store.filteredDatabases.map((d) => d.id), [11]);
      // The canonical unfiltered lists stay intact for other consumers.
      expect(store.servers, hasLength(2));
      expect(store.databases, hasLength(2));

      store.setSearch('');
      expect(store.filteredServers, hasLength(2));
      expect(store.filteredDatabases, hasLength(2));
    });
  });
}
