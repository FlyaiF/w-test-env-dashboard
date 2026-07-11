import 'dart:convert';

import 'package:env_viewer/api/backend_client.dart';
import 'package:env_viewer/catalog/environment_store.dart';
import 'package:env_viewer/config/config_service.dart';
import 'package:env_viewer/config/config_store.dart';
import 'package:env_viewer/inventory/inventory_store.dart';
import 'package:env_viewer/pages/catalog/catalog_page.dart';
import 'package:env_viewer/services/access/access_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

EnvironmentStore _storeReturning(Object json) {
  return EnvironmentStore(
    BackendClient(
      baseUrl: 'http://test',
      httpClient: MockClient((_) async => _jsonResponse(json)),
    ),
  );
}

http.Response _jsonResponse(Object? body, [int statusCode = 200]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      statusCode,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Widget _wrap(EnvironmentStore store, {InventoryStore? inventoryStore}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<EnvironmentStore>.value(value: store),
      if (inventoryStore != null)
        ChangeNotifierProvider<InventoryStore>.value(value: inventoryStore),
      ChangeNotifierProvider<ConfigStore>.value(
        value: ConfigStore(AppConfig.empty()),
      ),
      Provider<AccessLauncher>(
        create: (_) => AccessLauncher(
          BackendClient(
            baseUrl: 'http://unused',
            httpClient: MockClient((_) async => http.Response('{}', 200)),
          ),
        ),
      ),
    ],
    child: const MaterialApp(home: Scaffold(body: CatalogPage())),
  );
}

void main() {
  testWidgets('renders the environment list and selected detail read-only', (
    tester,
  ) async {
    final store = _storeReturning([
      {
        'id': 1,
        'name': 'Alpha',
        'memo': '主集成环境',
        'components': [
          {
            'id': 10,
            'role': 'GATEWAY',
            'version': '1.2.3',
            'versionProbe': 'HTTP',
            'collectionStatus': 'OK',
            'url': 'https://alpha.test/gw',
          },
        ],
      },
      {'id': 2, 'name': 'Beta', 'memo': null, 'components': []},
    ]);

    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();

    // List shows both environments.
    expect(find.text('Alpha'), findsWidgets);
    expect(find.text('Beta'), findsOneWidget);

    // First environment is auto-selected; its component renders with the
    // localized role label and version — read-only (no edit/save controls).
    expect(find.text('网关'), findsOneWidget);
    expect(find.text('1.2.3'), findsOneWidget);
    expect(find.text('正常'), findsOneWidget); // collection status chip
    expect(find.text('HTTP 接口'), findsOneWidget); // version probe label
    expect(find.byIcon(Icons.save), findsNothing);
  });

  testWidgets('立即采集 button collects the selected environment in place', (
    tester,
  ) async {
    var refreshCalls = 0;
    final store = EnvironmentStore(
      BackendClient(
        baseUrl: 'http://test',
        httpClient: MockClient((req) async {
          if (req.method == 'POST' &&
              req.url.path == '/api/environments/1/refresh') {
            refreshCalls++;
            return _jsonResponse({
              'id': 1,
              'name': 'Alpha',
              'memo': null,
              'components': [
                {
                  'id': 10,
                  'role': 'GATEWAY',
                  'version': '2.0.0',
                  'versionUpdatedAt': '2026-07-01T02:30:00Z',
                  'collectionStatus': 'OK',
                },
              ],
            });
          }
          if (req.url.path == '/api/environments') {
            return _jsonResponse([
              {
                'id': 1,
                'name': 'Alpha',
                'memo': null,
                'components': [
                  {'id': 10, 'role': 'GATEWAY', 'version': '1.2.3'},
                ],
              },
            ]);
          }
          return http.Response('[]', 200); // servers/databases refs
        }),
      ),
    );

    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();
    expect(find.text('1.2.3'), findsOneWidget);

    await tester.tap(find.byTooltip('立即采集'));
    await tester.pumpAndSettle();

    expect(refreshCalls, 1);
    expect(find.text('2.0.0'), findsOneWidget); // fresh view swapped in place
    expect(find.text('1.2.3'), findsNothing);
    expect(find.textContaining('已采集'), findsOneWidget); // success snackbar
  });

  testWidgets('shows an empty state when the backend returns nothing', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_storeReturning([])));
    await tester.pumpAndSettle();

    expect(find.text('暂无环境'), findsOneWidget);
  });

  testWidgets('header remains usable at compact desktop widths', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(_storeReturning([])));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('环境目录'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '新建环境'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('shows a localized error banner when the backend fails', (
    tester,
  ) async {
    final store = EnvironmentStore(
      BackendClient(
        baseUrl: 'http://test',
        httpClient: MockClient((_) async => http.Response('boom', 500)),
      ),
    );

    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();

    expect(find.textContaining('500'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('resolves Component references from canonical InventoryStore', (
    tester,
  ) async {
    final environmentStore = EnvironmentStore(
      BackendClient(
        baseUrl: 'http://catalog',
        httpClient: MockClient((req) async {
          if (req.url.path == '/api/environments') {
            return _jsonResponse([
              {
                'id': 1,
                'name': 'Alpha',
                'components': [
                  {
                    'id': 10,
                    'role': 'APP',
                    'serverId': 7,
                    'databaseIds': [9],
                  },
                ],
              },
            ]);
          }
          return _jsonResponse([]);
        }),
      ),
    );
    final inventoryStore = InventoryStore(
      BackendClient(
        baseUrl: 'http://inventory',
        httpClient: MockClient((req) async {
          if (req.url.path == '/api/servers') {
            return _jsonResponse([
              {'id': 7, 'host': 'srv-main', 'os': 'LINUX', 'ssh': null},
            ]);
          }
          if (req.url.path == '/api/databases') {
            return _jsonResponse([
              {
                'id': 9,
                'role': 'business',
                'type': 'ORACLE',
                'connection': {
                  'host': 'db-main',
                  'port': 1521,
                  'serviceName': 'ORCL',
                  'username': 'app',
                },
              },
            ]);
          }
          return _jsonResponse([]);
        }),
      ),
    );
    await inventoryStore.load();

    await tester.pumpWidget(
      _wrap(environmentStore, inventoryStore: inventoryStore),
    );
    await tester.pumpAndSettle();

    expect(find.text('srv-main'), findsWidgets);
    expect(find.text('业务库 · Oracle · db-main:1521/ORCL'), findsOneWidget);
  });
}
