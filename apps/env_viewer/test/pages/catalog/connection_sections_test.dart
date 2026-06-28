import 'dart:convert';

import 'package:env_viewer/api/backend_client.dart';
import 'package:env_viewer/catalog/environment_view.dart';
import 'package:env_viewer/pages/catalog/connection_sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

/// Serves brokered credential bundles from canned data keyed by id, so the
/// section widgets can be driven without a real backend. `secret == null` models
/// a resource with no stored password.
BackendClient _client({
  Map<int, Map<String, dynamic>> servers = const {},
  Map<int, Map<String, dynamic>> databases = const {},
}) {
  return BackendClient(
    baseUrl: 'http://test',
    httpClient: MockClient((req) async {
      final segs = req.url.pathSegments; // api, servers|databases, {id}, credentials
      final id = int.parse(segs[2]);
      final bundle = segs[1] == 'servers' ? servers[id] : databases[id];
      if (bundle == null) return http.Response('not found', 404);
      return http.Response(jsonEncode(bundle), 200);
    }),
  );
}

Widget _host(BackendClient client, Widget child) {
  return Provider<BackendClient>.value(
    value: client,
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('SshInfoSection', () {
    testWidgets('shows the address and masks the password until revealed', (
      tester,
    ) async {
      final client = _client(
        servers: {
          6: {
            'serverId': 6,
            'host': 'h',
            'port': 22,
            'username': 'ta66',
            'secret': 's3cr3t',
          },
        },
      );

      await tester.pumpWidget(
        _host(
          client,
          const SshInfoSection(
            serverId: 6,
            server: ServerRefView(
              id: 6,
              host: 'h',
              sshHost: 'h',
              sshPort: 22,
              sshUsername: 'ta66',
            ),
          ),
        ),
      );

      expect(find.text('ta66@h'), findsOneWidget);
      expect(find.text('••••••'), findsOneWidget);
      expect(find.text('s3cr3t'), findsNothing);

      await tester.tap(find.byTooltip('显示密码'));
      await tester.pumpAndSettle();

      expect(find.text('s3cr3t'), findsOneWidget);
      expect(find.text('••••••'), findsNothing);
    });

    testWidgets('reveal on a server with no stored secret warns and stays masked', (
      tester,
    ) async {
      final client = _client(
        servers: {
          7: {'serverId': 7, 'host': 'h', 'port': 22, 'username': 'u', 'secret': null},
        },
      );

      await tester.pumpWidget(
        _host(
          client,
          const SshInfoSection(
            serverId: 7,
            server: ServerRefView(id: 7, host: 'h', sshHost: 'h', sshUsername: 'u'),
          ),
        ),
      );

      await tester.tap(find.byTooltip('显示密码'));
      await tester.pumpAndSettle();

      expect(find.text('未配置密码'), findsOneWidget); // snackbar
      expect(find.text('••••••'), findsOneWidget); // still masked
    });
  });

  group('DatabaseInfoSection', () {
    testWidgets('one row per database; copy assembles the sqlplus string', (
      tester,
    ) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      final client = _client(
        databases: {
          9: {
            'databaseId': 9,
            'username': 'app',
            'host': '10.0.0.1',
            'port': 1521,
            'serviceName': 'ORCL',
            'secret': 'pw',
          },
        },
      );

      await tester.pumpWidget(
        _host(
          client,
          const DatabaseInfoSection(
            databaseIds: [9],
            databaseRefs: {
              9: DatabaseRefView(
                id: 9,
                roleLabel: '业务库',
                typeLabel: 'Oracle',
                host: '10.0.0.1',
                port: 1521,
                serviceName: 'ORCL',
              ),
            },
          ),
        ),
      );

      expect(find.text('业务库 · Oracle · 10.0.0.1:1521/ORCL'), findsOneWidget);

      await tester.tap(find.byTooltip('复制 sqlplus 连接串'));
      await tester.pumpAndSettle();

      expect(copied, ['app/pw@10.0.0.1:1521/ORCL']);
      expect(find.text('已复制连接串'), findsOneWidget); // snackbar
    });

    testWidgets('an unresolved database falls back to #id and still copies', (
      tester,
    ) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      final client = _client(
        databases: {
          12: {
            'databaseId': 12,
            'username': 'app',
            'host': 'db',
            'port': 1521,
            'serviceName': 'X',
            'secret': null,
          },
        },
      );

      await tester.pumpWidget(
        _host(
          client,
          const DatabaseInfoSection(databaseIds: [12], databaseRefs: {}),
        ),
      );

      expect(find.text('#12'), findsOneWidget);

      await tester.tap(find.byTooltip('复制 sqlplus 连接串'));
      await tester.pumpAndSettle();

      expect(copied, ['app@db:1521/X']); // no password → no /pw segment
      expect(find.text('已复制连接串（无密码）'), findsOneWidget);
    });
  });
}
