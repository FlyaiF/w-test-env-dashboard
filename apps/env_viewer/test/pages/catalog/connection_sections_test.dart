import 'dart:async';
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
  Future<http.Response> Function(http.Request request)? handler,
}) {
  return BackendClient(
    baseUrl: 'http://test',
    httpClient: MockClient((req) async {
      if (handler != null) return handler(req);
      final segs =
          req.url.pathSegments; // api, servers|databases, {id}, credentials
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

    testWidgets('every reveal and copy refetches; hiding drops the secret', (
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

      var requests = 0;
      final client = _client(
        handler: (req) async {
          requests++;
          return http.Response(
            jsonEncode({
              'serverId': 6,
              'host': 'h',
              'port': 22,
              'username': 'u',
              'secret': 'secret-$requests',
            }),
            200,
          );
        },
      );

      await tester.pumpWidget(
        _host(
          client,
          const SshInfoSection(
            serverId: 6,
            server: ServerRefView(id: 6, host: 'h'),
          ),
        ),
      );

      await tester.tap(find.byTooltip('显示密码'));
      await tester.pumpAndSettle();
      expect(find.text('secret-1'), findsOneWidget);

      await tester.tap(find.byTooltip('复制密码'));
      await tester.pumpAndSettle();
      expect(copied, ['secret-2']);
      expect(find.text('secret-2'), findsOneWidget);

      await tester.tap(find.byTooltip('隐藏密码'));
      await tester.pumpAndSettle();
      expect(find.text('secret-2'), findsNothing);
      expect(find.text('••••••'), findsOneWidget);

      await tester.tap(find.byTooltip('显示密码'));
      await tester.pumpAndSettle();
      expect(find.text('secret-3'), findsOneWidget);
      expect(requests, 3);
    });

    testWidgets('changing Server clears a revealed secret before refetching', (
      tester,
    ) async {
      final client = _client(
        servers: {
          6: {
            'serverId': 6,
            'host': 'a',
            'port': 22,
            'username': 'u',
            'secret': 'server-a-secret',
          },
          7: {
            'serverId': 7,
            'host': 'b',
            'port': 22,
            'username': 'u',
            'secret': 'server-b-secret',
          },
        },
      );

      await tester.pumpWidget(
        _host(
          client,
          const SshInfoSection(
            serverId: 6,
            server: ServerRefView(id: 6, host: 'a'),
          ),
        ),
      );
      await tester.tap(find.byTooltip('显示密码'));
      await tester.pumpAndSettle();
      expect(find.text('server-a-secret'), findsOneWidget);

      await tester.pumpWidget(
        _host(
          client,
          const SshInfoSection(
            serverId: 7,
            server: ServerRefView(id: 7, host: 'b'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('server-a-secret'), findsNothing);
      expect(find.text('••••••'), findsOneWidget);
      await tester.tap(find.byTooltip('显示密码'));
      await tester.pumpAndSettle();
      expect(find.text('server-b-secret'), findsOneWidget);
    });

    testWidgets('an in-flight response from the previous Server is ignored', (
      tester,
    ) async {
      final firstResponse = Completer<http.Response>();
      final client = _client(
        handler: (req) async {
          final id = int.parse(req.url.pathSegments[2]);
          if (id == 6) return firstResponse.future;
          return http.Response(
            jsonEncode({
              'serverId': 7,
              'host': 'b',
              'port': 22,
              'username': 'u',
              'secret': 'server-b-secret',
            }),
            200,
          );
        },
      );

      await tester.pumpWidget(
        _host(
          client,
          const SshInfoSection(
            serverId: 6,
            server: ServerRefView(id: 6, host: 'a'),
          ),
        ),
      );
      await tester.tap(find.byTooltip('显示密码'));
      await tester.pump();

      await tester.pumpWidget(
        _host(
          client,
          const SshInfoSection(
            serverId: 7,
            server: ServerRefView(id: 7, host: 'b'),
          ),
        ),
      );
      firstResponse.complete(
        http.Response(
          jsonEncode({
            'serverId': 6,
            'host': 'a',
            'port': 22,
            'username': 'u',
            'secret': 'server-a-secret',
          }),
          200,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('server-a-secret'), findsNothing);
      expect(find.text('••••••'), findsOneWidget);
    });

    testWidgets(
      'reveal on a server with no stored secret warns and stays masked',
      (tester) async {
        final client = _client(
          servers: {
            7: {
              'serverId': 7,
              'host': 'h',
              'port': 22,
              'username': 'u',
              'secret': null,
            },
          },
        );

        await tester.pumpWidget(
          _host(
            client,
            const SshInfoSection(
              serverId: 7,
              server: ServerRefView(
                id: 7,
                host: 'h',
                sshHost: 'h',
                sshUsername: 'u',
              ),
            ),
          ),
        );

        await tester.tap(find.byTooltip('显示密码'));
        await tester.pumpAndSettle();

        expect(find.text('未配置密码'), findsOneWidget); // snackbar
        expect(find.text('••••••'), findsOneWidget); // still masked
      },
    );
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

    testWidgets('an in-flight response from a removed database is ignored', (
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

      final oldResponse = Completer<http.Response>();
      final client = _client(
        handler: (req) async {
          final id = int.parse(req.url.pathSegments[2]);
          if (id == 9) return oldResponse.future;
          return http.Response(
            jsonEncode({
              'databaseId': 12,
              'username': 'next',
              'host': 'new-db',
              'port': 1521,
              'serviceName': 'NEXT',
              'secret': 'new-secret',
            }),
            200,
          );
        },
      );

      await tester.pumpWidget(
        _host(
          client,
          const DatabaseInfoSection(databaseIds: [9], databaseRefs: {}),
        ),
      );
      await tester.tap(find.byTooltip('复制 sqlplus 连接串'));
      await tester.pump();

      await tester.pumpWidget(
        _host(
          client,
          const DatabaseInfoSection(databaseIds: [12], databaseRefs: {}),
        ),
      );
      oldResponse.complete(
        http.Response(
          jsonEncode({
            'databaseId': 9,
            'username': 'old',
            'host': 'old-db',
            'port': 1521,
            'serviceName': 'OLD',
            'secret': 'old-secret',
          }),
          200,
        ),
      );
      await tester.pumpAndSettle();

      expect(copied, isEmpty);
      expect(find.text('已复制连接串'), findsNothing);
      expect(find.text('#12'), findsOneWidget);

      await tester.tap(find.byTooltip('复制 sqlplus 连接串'));
      await tester.pumpAndSettle();
      expect(copied, ['next/new-secret@new-db:1521/NEXT']);
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
