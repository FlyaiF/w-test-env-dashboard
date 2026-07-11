import 'dart:async';
import 'dart:convert';

import 'package:env_viewer/api/backend_client.dart';
import 'package:env_viewer/inventory/inventory_store.dart';
import 'package:env_viewer/pages/inventory/inventory_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

const _server = {
  'id': 7,
  'host': 'app01.internal',
  'os': 'LINUX',
  'ssh': {'host': 'gateway.internal', 'port': 2222, 'username': 'deploy'},
};

const _database = {
  'id': 9,
  'role': 'business',
  'type': 'ORACLE',
  'connection': {
    'host': 'db01.internal',
    'port': 1521,
    'serviceName': 'ORCL',
    'username': 'app_user',
  },
};

class _HttpInventoryFixture {
  _HttpInventoryFixture({
    List<Map<String, dynamic>> servers = const [],
    List<Map<String, dynamic>> databases = const [],
  }) : servers = servers.map(Map<String, dynamic>.from).toList(),
       databases = databases.map(Map<String, dynamic>.from).toList();

  final List<Map<String, dynamic>> servers;
  final List<Map<String, dynamic>> databases;
  final List<http.Request> requests = [];
  Completer<void>? loadGate;
  bool failLoads = false;
  bool conflictServerDelete = false;
  bool conflictDatabaseDelete = false;
  int serverUsageFailuresRemaining = 0;
  List<Map<String, dynamic>> serverUsage = const [];
  List<Map<String, dynamic>> databaseUsage = const [];

  InventoryStore createStore() => InventoryStore(
    BackendClient(baseUrl: 'http://test', httpClient: MockClient(handle)),
  );

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    if (request.method == 'GET' &&
        (path == '/api/servers' || path == '/api/databases')) {
      final gate = loadGate;
      if (gate != null) await gate.future;
      if (failLoads) {
        return _problem(503, '后端暂不可用');
      }
      return _json(path == '/api/servers' ? servers : databases);
    }

    if (request.method == 'POST' && path == '/api/servers') {
      final created = <String, dynamic>{
        'id': 70,
        ...jsonDecode(request.body) as Map<String, dynamic>,
      };
      servers.add(created);
      return _json(created, 201);
    }
    if (request.method == 'PUT' && path.startsWith('/api/servers/')) {
      final id = int.parse(request.url.pathSegments[2]);
      final updated = <String, dynamic>{
        'id': id,
        ...jsonDecode(request.body) as Map<String, dynamic>,
      };
      servers[servers.indexWhere((item) => item['id'] == id)] = updated;
      return _json(updated);
    }
    if (request.method == 'DELETE' && path.startsWith('/api/servers/')) {
      if (conflictServerDelete) {
        return _problem(409, '该服务器仍被环境引用');
      }
      final id = int.parse(request.url.pathSegments[2]);
      servers.removeWhere((item) => item['id'] == id);
      return http.Response('', 204);
    }
    if (request.method == 'GET' &&
        path.endsWith('/environments') &&
        path.startsWith('/api/servers/')) {
      if (serverUsageFailuresRemaining > 0) {
        serverUsageFailuresRemaining--;
        return _problem(503, '使用情况暂不可用');
      }
      return _json(serverUsage);
    }

    if (request.method == 'POST' && path == '/api/databases') {
      final created = <String, dynamic>{
        'id': 90,
        ...jsonDecode(request.body) as Map<String, dynamic>,
      };
      databases.add(created);
      return _json(created, 201);
    }
    if (request.method == 'PUT' && path.startsWith('/api/databases/')) {
      final id = int.parse(request.url.pathSegments[2]);
      final updated = <String, dynamic>{
        'id': id,
        ...jsonDecode(request.body) as Map<String, dynamic>,
      };
      databases[databases.indexWhere((item) => item['id'] == id)] = updated;
      return _json(updated);
    }
    if (request.method == 'DELETE' && path.startsWith('/api/databases/')) {
      if (conflictDatabaseDelete) {
        return _problem(409, '该数据库仍被环境引用');
      }
      final id = int.parse(request.url.pathSegments[2]);
      databases.removeWhere((item) => item['id'] == id);
      return http.Response('', 204);
    }
    if (request.method == 'GET' &&
        path.endsWith('/environments') &&
        path.startsWith('/api/databases/')) {
      return _json(databaseUsage);
    }

    return _problem(404, 'unexpected ${request.method} $path');
  }

  http.Request request(String method, String path) => requests.lastWhere(
    (request) => request.method == method && request.url.path == path,
  );
}

http.Response _json(Object? body, [int statusCode = 200]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      statusCode,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

http.Response _problem(int statusCode, String detail) => _json({
  'title': 'Request failed',
  'detail': detail,
  'status': statusCode,
}, statusCode);

Widget _host(InventoryStore store) {
  return ChangeNotifierProvider<InventoryStore>.value(
    value: store,
    child: const MaterialApp(home: Scaffold(body: InventoryPage())),
  );
}

Future<void> _switchToDatabases(WidgetTester tester) async {
  await tester.tap(find.text('数据库').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('compact tabs search and render stable resource cards', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = _HttpInventoryFixture(
      servers: [Map<String, dynamic>.from(_server)],
      databases: [Map<String, dynamic>.from(_database)],
    );

    await tester.pumpWidget(_host(fixture.createStore()));
    await tester.pumpAndSettle();

    expect(find.text('资源清单'), findsOneWidget);
    expect(find.byKey(const ValueKey('server-card-7')), findsOneWidget);
    expect(find.text('deploy@gateway.internal:2222'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(
      find.byKey(const ValueKey('inventory-search-field')),
      'missing',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('server-card-7')), findsNothing);
    expect(find.text('没有匹配的服务器'), findsOneWidget);

    await _switchToDatabases(tester);
    expect(find.byKey(const ValueKey('database-card-9')), findsOneWidget);
    expect(find.text('db01.internal:1521/ORCL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('initial loading resolves to the empty states', (tester) async {
    final fixture = _HttpInventoryFixture()..loadGate = Completer<void>();
    await tester.pumpWidget(_host(fixture.createStore()));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('inventory-initial-loading')),
      findsOneWidget,
    );

    fixture.loadGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('暂无服务器'), findsOneWidget);
    await _switchToDatabases(tester);
    expect(find.text('暂无数据库'), findsOneWidget);
  });

  testWidgets('load errors stay visible and can be retried', (tester) async {
    final fixture = _HttpInventoryFixture()..failLoads = true;
    await tester.pumpWidget(_host(fixture.createStore()));
    await tester.pumpAndSettle();

    expect(find.text('后端暂不可用（503）'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    fixture.failLoads = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.textContaining('503'), findsNothing);
    expect(find.text('暂无服务器'), findsOneWidget);
  });

  testWidgets('server create and edit submit through the HTTP boundary', (
    tester,
  ) async {
    final oldServer = Map<String, dynamic>.from(_server)
      ..['host'] = 'old.internal'
      ..['ssh'] = null;
    final fixture = _HttpInventoryFixture(servers: [oldServer]);
    await tester.pumpWidget(_host(fixture.createStore()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('inventory-create-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('server-host-field')),
      'new.internal',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final create = fixture.request('POST', '/api/servers');
    expect(jsonDecode(create.body)['host'], 'new.internal');
    expect(jsonDecode(create.body).toString(), isNot(contains('password')));
    expect(find.text('服务器已创建'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('server-edit-7')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('server-host-field')),
      'edited.internal',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final update = fixture.request('PUT', '/api/servers/7');
    expect(jsonDecode(update.body)['host'], 'edited.internal');
    expect(find.text('服务器已更新'), findsOneWidget);
  });

  testWidgets('database create and edit submit through the HTTP boundary', (
    tester,
  ) async {
    final fixture = _HttpInventoryFixture(
      databases: [Map<String, dynamic>.from(_database)],
    );
    await tester.pumpWidget(_host(fixture.createStore()));
    await tester.pumpAndSettle();
    await _switchToDatabases(tester);

    await tester.tap(find.byKey(const ValueKey('inventory-create-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('database-role-field')),
      'intermediate',
    );
    await tester.enterText(
      find.byKey(const ValueKey('database-host-field')),
      'new-db.internal',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final create = fixture.request('POST', '/api/databases');
    final createBody = jsonDecode(create.body) as Map<String, dynamic>;
    expect(createBody['role'], 'intermediate');
    expect((createBody['connection'] as Map)['host'], 'new-db.internal');
    expect(createBody.toString(), isNot(contains('password')));
    expect(find.text('数据库已创建'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('database-edit-9')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('database-role-field')),
      'primary',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    final update = fixture.request('PUT', '/api/databases/9');
    expect(jsonDecode(update.body)['role'], 'primary');
    expect(find.text('数据库已更新'), findsOneWidget);
  });

  testWidgets('a referenced server delete surfaces the backend 409', (
    tester,
  ) async {
    final fixture = _HttpInventoryFixture(
      servers: [Map<String, dynamic>.from(_server)],
    )..conflictServerDelete = true;
    await tester.pumpWidget(_host(fixture.createStore()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('server-delete-7')));
    await tester.pumpAndSettle();
    expect(find.text('删除服务器'), findsOneWidget);
    expect(
      fixture.requests.where((request) => request.method == 'DELETE'),
      isEmpty,
    );

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(fixture.request('DELETE', '/api/servers/7'), isNotNull);
    expect(find.textContaining('409'), findsWidgets);
    expect(find.textContaining('仍被环境引用'), findsWidgets);
  });

  testWidgets('database delete is confirmed before its HTTP mutation', (
    tester,
  ) async {
    final fixture = _HttpInventoryFixture(
      databases: [Map<String, dynamic>.from(_database)],
    );
    await tester.pumpWidget(_host(fixture.createStore()));
    await tester.pumpAndSettle();
    await _switchToDatabases(tester);

    await tester.tap(find.byKey(const ValueKey('database-delete-9')));
    await tester.pumpAndSettle();
    expect(find.text('删除数据库'), findsOneWidget);
    expect(
      fixture.requests.where((request) => request.method == 'DELETE'),
      isEmpty,
    );

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(fixture.request('DELETE', '/api/databases/9'), isNotNull);
    expect(find.text('数据库已删除'), findsOneWidget);
    expect(find.byKey(const ValueKey('database-card-9')), findsNothing);
  });

  testWidgets('a referenced database delete surfaces the backend 409', (
    tester,
  ) async {
    final fixture = _HttpInventoryFixture(
      databases: [Map<String, dynamic>.from(_database)],
    )..conflictDatabaseDelete = true;
    await tester.pumpWidget(_host(fixture.createStore()));
    await tester.pumpAndSettle();
    await _switchToDatabases(tester);

    await tester.tap(find.byKey(const ValueKey('database-delete-9')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(fixture.request('DELETE', '/api/databases/9'), isNotNull);
    expect(find.textContaining('409'), findsWidgets);
    expect(find.textContaining('数据库仍被环境引用'), findsWidgets);
    expect(find.byKey(const ValueKey('database-card-9')), findsOneWidget);
  });

  testWidgets('usage dialogs show environments and only matching components', (
    tester,
  ) async {
    final usage = [
      {
        'id': 1,
        'name': 'Alpha',
        'memo': null,
        'components': [
          {
            'id': 101,
            'role': 'GATEWAY',
            'serverId': 7,
            'databaseIds': [9],
          },
          {
            'id': 102,
            'role': 'UI',
            'serverId': 8,
            'databaseIds': [10],
          },
        ],
      },
    ];
    final fixture =
        _HttpInventoryFixture(
            servers: [Map<String, dynamic>.from(_server)],
            databases: [Map<String, dynamic>.from(_database)],
          )
          ..serverUsage = usage
          ..databaseUsage = usage;
    await tester.pumpWidget(_host(fixture.createStore()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('server-usage-7')));
    await tester.pumpAndSettle();
    expect(find.textContaining('服务器使用情况'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('网关'), findsOneWidget);
    expect(find.text('界面'), findsNothing);
    expect(fixture.request('GET', '/api/servers/7/environments'), isNotNull);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    await _switchToDatabases(tester);
    await tester.tap(find.byKey(const ValueKey('database-usage-9')));
    await tester.pumpAndSettle();
    expect(find.textContaining('数据库使用情况'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('网关'), findsOneWidget);
    expect(find.text('界面'), findsNothing);
    expect(fixture.request('GET', '/api/databases/9/environments'), isNotNull);
  });

  testWidgets('a failed usage lookup retries in the open dialog', (
    tester,
  ) async {
    final fixture =
        _HttpInventoryFixture(servers: [Map<String, dynamic>.from(_server)])
          ..serverUsageFailuresRemaining = 1
          ..serverUsage = [
            {
              'id': 1,
              'name': 'Alpha',
              'components': [
                {'id': 101, 'role': 'GATEWAY', 'serverId': 7},
              ],
            },
          ];
    await tester.pumpWidget(_host(fixture.createStore()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('server-usage-7')));
    await tester.pumpAndSettle();
    expect(find.textContaining('加载使用情况失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('网关'), findsOneWidget);
    expect(
      fixture.requests.where(
        (request) => request.url.path == '/api/servers/7/environments',
      ),
      hasLength(2),
    );
  });
}
