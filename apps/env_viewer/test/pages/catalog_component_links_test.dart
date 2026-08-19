import 'dart:async';
import 'dart:convert';

import 'package:env_viewer/api/backend_client.dart';
import 'package:env_viewer/api/dto/component_links_input.dart';
import 'package:env_viewer/catalog/environment_store.dart';
import 'package:env_viewer/catalog/environment_view.dart';
import 'package:env_viewer/config/config_service.dart';
import 'package:env_viewer/config/config_store.dart';
import 'package:env_viewer/inventory/inventory_store.dart';
import 'package:env_viewer/inventory/inventory_view.dart';
import 'package:env_viewer/pages/catalog/catalog_link_editor.dart';
import 'package:env_viewer/pages/catalog/catalog_page.dart';
import 'package:env_viewer/services/access/access_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Widget _catalogHost(BackendClient client, InventoryStore inventoryStore) {
  return MultiProvider(
    providers: [
      Provider<BackendClient>.value(value: client),
      Provider<AccessLauncher>.value(value: AccessLauncher(client)),
      ChangeNotifierProvider<EnvironmentStore>(
        create: (_) => EnvironmentStore(client),
      ),
      ChangeNotifierProvider<InventoryStore>.value(value: inventoryStore),
      ChangeNotifierProvider<ConfigStore>.value(
        value: ConfigStore(AppConfig.empty()),
      ),
    ],
    child: const MaterialApp(home: Scaffold(body: CatalogPage())),
  );
}

void main() {
  testWidgets('links a Component to one Server and selected Databases', (
    tester,
  ) async {
    // Desktop-sized surface so both dialog list panes show several rows.
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    Map<String, dynamic>? submitted;
    final client = BackendClient(
      baseUrl: 'http://test',
      httpClient: MockClient((request) async {
        if (request.method == 'PUT' &&
            request.url.path == '/api/components/10/links') {
          submitted = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({
            'id': 10,
            'role': 'APP',
            'serverId': 2,
            'databaseIds': [4],
          });
        }
        if (request.url.path == '/api/environments') {
          final linked = submitted != null;
          return _json([
            {
              'id': 1,
              'name': 'Alpha',
              'components': [
                {
                  'id': 10,
                  'role': 'APP',
                  'serverId': linked ? 2 : 1,
                  'databaseIds': linked ? [4] : [3],
                },
              ],
            },
          ]);
        }
        if (request.url.path == '/api/servers') {
          return _json([
            {'id': 1, 'host': 'srv-a', 'os': 'LINUX', 'ssh': null},
            {'id': 2, 'host': 'srv-b', 'os': 'WINDOWS', 'ssh': null},
          ]);
        }
        if (request.url.path == '/api/databases') {
          return _json([
            {
              'id': 3,
              'role': 'business',
              'type': 'ORACLE',
              'connection': {'host': 'db-a'},
            },
            {
              'id': 4,
              'role': 'intermediate',
              'type': 'DAMENG',
              'connection': {'host': 'db-b'},
            },
          ]);
        }
        return http.Response('not found', 404);
      }),
    );
    final inventoryStore = InventoryStore(client);
    await inventoryStore.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<BackendClient>.value(value: client),
          Provider<AccessLauncher>.value(value: AccessLauncher(client)),
          ChangeNotifierProvider<EnvironmentStore>(
            create: (_) => EnvironmentStore(client),
          ),
          ChangeNotifierProvider<InventoryStore>.value(value: inventoryStore),
          ChangeNotifierProvider<ConfigStore>.value(
            value: ConfigStore(AppConfig.empty()),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: CatalogPage())),
      ),
    );
    await tester.pumpAndSettle();

    // Management actions live in the expanded row body.
    await tester.tap(find.text('主服务'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关联资源'));
    await tester.pumpAndSettle();

    // Rows are annotated with the environments already using each resource.
    expect(find.text('用于：Alpha'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('component-links-server-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('component-links-database-3')));
    await tester.tap(find.byKey(const ValueKey('component-links-database-4')));
    await tester.tap(find.byKey(const ValueKey('component-links-save')));
    await tester.pumpAndSettle();

    expect(submitted, {
      'serverId': 2,
      'databaseIds': [4],
    });
    expect(find.text('组件资源关联已更新'), findsOneWidget);
    expect(find.text('srv-b'), findsWidgets);
    expect(find.textContaining('中转库 · 达梦 · db-b'), findsOneWidget);
  });

  testWidgets('keeps link selections open when the backend rejects them', (
    tester,
  ) async {
    final client = BackendClient(
      baseUrl: 'http://test',
      httpClient: MockClient((request) async {
        if (request.method == 'PUT' &&
            request.url.path == '/api/components/10/links') {
          return _json({'detail': '数据库 #4 不存在'}, 409);
        }
        if (request.url.path == '/api/environments') {
          return _json([
            {
              'id': 1,
              'name': 'Alpha',
              'components': [
                {'id': 10, 'role': 'APP', 'databaseIds': <int>[]},
              ],
            },
          ]);
        }
        if (request.url.path == '/api/servers') return _json([]);
        if (request.url.path == '/api/databases') {
          return _json([
            {
              'id': 4,
              'role': 'business',
              'type': 'ORACLE',
              'connection': {'host': 'db-a'},
            },
          ]);
        }
        return http.Response('not found', 404);
      }),
    );
    final inventoryStore = InventoryStore(client);
    await inventoryStore.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<BackendClient>.value(value: client),
          Provider<AccessLauncher>.value(value: AccessLauncher(client)),
          ChangeNotifierProvider<EnvironmentStore>(
            create: (_) => EnvironmentStore(client),
          ),
          ChangeNotifierProvider<InventoryStore>.value(value: inventoryStore),
          ChangeNotifierProvider<ConfigStore>.value(
            value: ConfigStore(AppConfig.empty()),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: CatalogPage())),
      ),
    );
    await tester.pumpAndSettle();

    // Management actions live in the expanded row body.
    await tester.tap(find.text('主服务'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关联资源'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('component-links-database-4')));
    await tester.tap(find.byKey(const ValueKey('component-links-save')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('数据库 #4 不存在'), findsWidgets);
    final checkbox = tester.widget<CheckboxListTile>(
      find.byKey(const ValueKey('component-links-database-4')),
    );
    expect(checkbox.value, isTrue);
  });

  testWidgets('shows unresolved links and can clear all of them', (
    tester,
  ) async {
    ComponentLinksInput? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showComponentLinksEditor(
                context,
                component: const ComponentView(
                  id: 10,
                  roleLabel: '应用服务',
                  serverId: 99,
                  databaseIds: [88],
                  versionProbeLabel: '未配置',
                  collectionState: CollectionState.notCollected,
                  collectionStatusLabel: '未采集',
                ),
                servers: const [],
                databases: const [],
                onSave: (input) async {
                  submitted = input;
                  return null;
                },
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('#99（资源不存在）'), findsOneWidget);
    expect(find.text('#88（资源不存在）'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('component-links-server-none')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('component-links-database-88')));
    await tester.tap(find.byKey(const ValueKey('component-links-save')));
    await tester.pumpAndSettle();

    expect(submitted?.serverId, isNull);
    expect(submitted?.databaseIds, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'disambiguates same-address resources and filters through search',
    (tester) async {
      // Desktop-sized surface so both dialog list panes show several rows.
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      const servers = [
        ServerView(id: 1, host: '10.20.162.81', sshUsername: 'root'),
        ServerView(id: 2, host: '10.20.162.81-ta66', sshUsername: 'ta66'),
      ];
      const databases = [
        DatabaseView(
          id: 41,
          roleLabel: '业务库',
          typeLabel: 'Oracle',
          host: '10.20.154.151',
          port: 1521,
          serviceName: 'orcl',
          username: 'trade1',
        ),
        DatabaseView(
          id: 42,
          roleLabel: '业务库',
          typeLabel: 'Oracle',
          host: '10.20.154.151',
          port: 1521,
          serviceName: 'orcl',
          username: 'trade2',
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showComponentLinksEditor(
                  context,
                  component: const ComponentView(
                    id: 10,
                    roleLabel: '应用服务',
                    serverId: 1,
                    databaseIds: [41],
                    versionProbeLabel: '未配置',
                    collectionState: CollectionState.notCollected,
                    collectionStatusLabel: '未采集',
                  ),
                  servers: servers,
                  databases: databases,
                  serverUsage: const {
                    1: ['山东主干'],
                    2: ['天津主干'],
                  },
                  databaseUsage: const {
                    41: ['山东主干'],
                    42: ['天津主干'],
                  },
                  onSave: (_) async => null,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Servers show their SSH account inline: user@host.
      expect(find.text('root@10.20.162.81'), findsOneWidget);
      expect(find.text('ta66@10.20.162.81-ta66'), findsOneWidget);

      // Same-address databases are told apart by login user and usage.
      expect(
        find.text('业务库 · Oracle · trade1@10.20.154.151:1521/orcl'),
        findsOneWidget,
      );
      expect(
        find.text('业务库 · Oracle · trade2@10.20.154.151:1521/orcl'),
        findsOneWidget,
      );
      expect(find.text('用于：山东主干'), findsNWidgets(2));
      expect(find.text('用于：天津主干'), findsNWidgets(2));

      // Search hides non-matching rows but keeps the current selections.
      await tester.enterText(
        find.byKey(const ValueKey('component-links-search')),
        'ta66',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('component-links-server-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('component-links-server-1')),
        findsOneWidget, // selected server stays visible
      );
      expect(
        find.byKey(const ValueKey('component-links-database-41')),
        findsOneWidget, // selected database stays visible
      );
      expect(
        find.byKey(const ValueKey('component-links-database-42')),
        findsNothing,
      );

      // Environment names are searchable too.
      await tester.enterText(
        find.byKey(const ValueKey('component-links-search')),
        '天津',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('component-links-database-42')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('component-links-server-2')),
        findsOneWidget,
      );
    },
  );

  testWidgets('waits for the in-flight inventory load before opening', (
    tester,
  ) async {
    final inventoryGate = Completer<void>();
    var inventoryRequestCount = 0;
    final client = BackendClient(
      baseUrl: 'http://test',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/environments') {
          return _json([
            {
              'id': 1,
              'name': 'Alpha',
              'components': [
                {'id': 10, 'role': 'APP', 'databaseIds': <int>[]},
              ],
            },
          ]);
        }
        if (request.url.path == '/api/servers') {
          inventoryRequestCount++;
          await inventoryGate.future;
          return _json([
            {'id': 1, 'host': 'srv-a', 'os': 'LINUX'},
          ]);
        }
        if (request.url.path == '/api/databases') {
          inventoryRequestCount++;
          await inventoryGate.future;
          return _json([
            {
              'id': 3,
              'role': 'business',
              'type': 'ORACLE',
              'connection': {'host': 'db-a'},
            },
          ]);
        }
        return http.Response('not found', 404);
      }),
    );
    final inventoryStore = InventoryStore(client);
    final initialLoad = inventoryStore.load();

    await tester.pumpWidget(_catalogHost(client, inventoryStore));
    await tester.pumpAndSettle();
    // Management actions live in the expanded row body.
    await tester.tap(find.text('主服务'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关联资源'));
    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);

    inventoryGate.complete();
    await initialLoad;
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('业务库 · Oracle · db-a'), findsOneWidget);
    expect(find.text('srv-a'), findsOneWidget);
    expect(inventoryRequestCount, 2);
  });

  testWidgets(
    'surfaces inventory load failure instead of opening empty links',
    (tester) async {
      final client = BackendClient(
        baseUrl: 'http://test',
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/environments') {
            return _json([
              {
                'id': 1,
                'name': 'Alpha',
                'components': [
                  {'id': 10, 'role': 'APP', 'databaseIds': <int>[]},
                ],
              },
            ]);
          }
          if (request.url.path == '/api/servers') {
            return _json({'detail': '资源清单暂不可用'}, 503);
          }
          if (request.url.path == '/api/databases') return _json([]);
          return http.Response('not found', 404);
        }),
      );
      final inventoryStore = InventoryStore(client);

      await tester.pumpWidget(_catalogHost(client, inventoryStore));
      await tester.pumpAndSettle();
      // Management actions live in the expanded row body.
      await tester.tap(find.text('主服务'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关联资源'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('资源清单暂不可用'), findsOneWidget);
    },
  );
}
