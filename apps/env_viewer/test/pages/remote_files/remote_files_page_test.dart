import 'dart:convert';

import 'package:env_viewer/api/backend_client.dart';
import 'package:env_viewer/catalog/environment_store.dart';
import 'package:env_viewer/inventory/inventory_store.dart';
import 'package:env_viewer/pages/remote_files/remote_files_page.dart';
import 'package:env_viewer/remote_files/remote_file_store.dart';
import 'package:env_viewer/services/remote_file/remote_file_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

class _FakeSession extends RemoteFileSession {
  _FakeSession(RemoteFileSessionSpec spec)
    : super(
        host: spec.host,
        port: spec.port,
        username: spec.username,
        secret: spec.secret,
        path: spec.path,
        mode: spec.mode,
      );

  @override
  Future<void> connect() async {}
}

void main() {
  final environments = [
    {
      'id': 1,
      'name': '联调A',
      'components': [
        {'id': 11, 'role': 'GATEWAY', 'serverId': 7, 'logLocation': '/logs/gw.log'},
        {'id': 12, 'role': 'UI', 'serverId': 7, 'logLocation': null},
        {'id': 13, 'role': 'APP', 'serverId': null, 'logLocation': '/x'},
      ],
    },
  ];
  final servers = [
    {'id': 7, 'host': 'srv-a', 'sshPort': 22, 'hasSecret': true},
  ];
  final credential = {
    'serverId': 7,
    'host': '10.0.0.5',
    'port': 22,
    'username': 'app',
    'secret': 's3cret',
  };

  Widget harness() {
    final client = BackendClient(
      baseUrl: 'http://test',
      httpClient: MockClient((request) async {
        final body = switch (request.url.path) {
          '/api/environments' => jsonEncode(environments),
          '/api/servers' => jsonEncode(servers),
          '/api/databases' => '[]',
          '/api/servers/7/credentials' => jsonEncode(credential),
          _ => '[]',
        };
        return http.Response.bytes(
          utf8.encode(body),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    return MultiProvider(
      providers: [
        Provider<BackendClient>.value(value: client),
        ChangeNotifierProvider(create: (_) => EnvironmentStore(client)),
        ChangeNotifierProvider(create: (_) => InventoryStore(client)),
        ChangeNotifierProvider(
          create: (_) => RemoteFileStore(
            client,
            sessionFactory: _FakeSession.new,
          ),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: RemoteFilesPage())),
    );
  }

  testWidgets('lists hosted components and flags ones without a 日志位置', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // Components on a Server appear; the serverless one does not.
    expect(find.text('联调A'), findsOneWidget);
    expect(find.text('网关'), findsOneWidget);
    expect(find.text('/logs/gw.log'), findsOneWidget);
    expect(find.text('未配置日志位置'), findsOneWidget);
    expect(find.text('应用'), findsNothing);

    // Nothing open yet: the empty state invites both entry paths.
    expect(find.textContaining('从左侧选择组件'), findsOneWidget);
  });

  testWidgets('opening a preset creates a follow tab silently', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('网关'));
    // Bounded pumps: the connecting spinner animates forever, so
    // pumpAndSettle would never settle.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The tab strip shows the opened session; no credential dialog appeared
    // because the broker returned a stored secret.
    expect(find.text('联调A · 网关'), findsWidgets);
    expect(find.text('密码'), findsNothing);
  });
}
