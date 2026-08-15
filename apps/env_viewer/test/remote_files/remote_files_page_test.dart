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

/// Session that records instead of dialing SSH.
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

/// Session that reports connected and serves canned directory listings, so
/// the free-path bar borrows a live lister without dialing SSH.
class _ListingSession extends _FakeSession {
  _ListingSession(super.spec);

  static const listings = {
    '/logs/': ['app/', 'gw.log'],
    '/logs/app/': ['archive/', 'today.log'],
  };

  @override
  Future<void> connect() async {
    status = RemoteFileStatus.connected;
  }

  @override
  Future<List<String>> listDirectory(String dirPath) async =>
      listings[dirPath] ?? const [];
}

void main() {
  BackendClient client() {
    return BackendClient(
      baseUrl: 'http://test',
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/credentials')) {
          return http.Response(
            jsonEncode({
              'serverId': 7,
              'host': '10.0.0.5',
              'port': 22,
              'username': 'app',
              'secret': 's3cret',
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.url.path == '/api/servers') {
          // One known server so the free-path bar has a selected server and
          // suggestion sources resolve.
          return http.Response(
            jsonEncode([
              {'id': 7, 'host': '10.0.0.5', 'os': 'LINUX', 'hasSecret': true},
            ]),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
  }

  Widget wrap(RemoteFileStore store) {
    final backend = client();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<EnvironmentStore>(
          create: (_) => EnvironmentStore(backend),
        ),
        ChangeNotifierProvider<InventoryStore>(
          create: (_) => InventoryStore(backend),
        ),
        ChangeNotifierProvider<RemoteFileStore>.value(value: store),
      ],
      child: const MaterialApp(home: Scaffold(body: RemoteFilesPage())),
    );
  }

  RemoteFileStore makeStore() =>
      RemoteFileStore(client(), sessionFactory: _FakeSession.new);

  String pathFieldText(WidgetTester tester) {
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byType(RemoteFilesPage),
        matching: find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText != null,
        ),
      ),
    );
    return field.controller!.text;
  }

  testWidgets('path bar follows the active tab across switches', (
    tester,
  ) async {
    final store = makeStore();
    await store.open(
      serverId: 7,
      title: 'A · 网关',
      path: '/logs/gw.log',
      mode: RemoteFileMode.view,
    );
    await store.open(
      serverId: 7,
      title: 'A · 应用',
      path: '/logs/app.log',
      mode: RemoteFileMode.view,
    );

    await tester.pumpWidget(wrap(store));
    await tester.pump();

    // Seeded from the active (last-opened) tab.
    expect(pathFieldText(tester), '/logs/app.log');

    store.select(0);
    await tester.pump();
    expect(pathFieldText(tester), '/logs/gw.log');
  });

  testWidgets('a long auto-filled path scrolls to show its tail', (
    tester,
  ) async {
    final store = makeStore();
    final longPath =
        '/home/ta66/GTZG/trust-ops/very/deep/directory/structure/logs/'
        'app-server-2026-08-02.log';
    await store.open(
      serverId: 7,
      title: 'A · 应用',
      path: longPath,
      mode: RemoteFileMode.view,
    );

    await tester.pumpWidget(wrap(store));
    await tester.pump();
    await tester.pump(); // post-frame scroll-to-end

    final field = tester.widget<TextField>(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText != null,
      ),
    );
    final scroll = field.scrollController!;
    expect(scroll.hasClients, isTrue);
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    expect(scroll.offset, scroll.position.maxScrollExtent);
  });

  testWidgets('suggestions lead with the differing tail segment', (
    tester,
  ) async {
    final store = makeStore();
    await store.open(
      serverId: 7,
      title: 'A · 网关',
      path: '/home/ta66/SDZG/dtl-web-starter/logs/gw.log',
      mode: RemoteFileMode.view,
    );
    await store.open(
      serverId: 7,
      title: 'A · 应用',
      path: '/home/ta66/SDZG/dtl-web-starter/logs/app.log',
      mode: RemoteFileMode.view,
    );

    await tester.pumpWidget(wrap(store));
    // Two pumps: one for the post-frame store loads, one so the inventory's
    // arrival rebuilds the bar (its server selection gates the suggestions).
    await tester.pump();
    await tester.pump();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText != null,
      ),
      'log',
    );
    // Not pumpAndSettle: the active tab's connecting spinner animates forever.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The overlay renders the file name on its own, not one long
    // identical-looking path per row.
    expect(find.text('gw.log'), findsOneWidget);
    expect(find.text('app.log'), findsOneWidget);
    expect(find.text('/home/ta66/SDZG/dtl-web-starter/logs/'), findsNWidgets(2));
  });

  testWidgets('picking a directory continues the walk; a file ends it', (
    tester,
  ) async {
    final store = RemoteFileStore(client(), sessionFactory: _ListingSession.new);
    await store.open(
      serverId: 7,
      title: 'A · 网关',
      path: '/logs/gw.log',
      mode: RemoteFileMode.view,
    );

    await tester.pumpWidget(wrap(store));
    await tester.pump();
    await tester.pump();

    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText != null,
    );
    await tester.enterText(field, '/logs/');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The live session lists /logs/: one directory, one file.
    expect(find.text('app/'), findsOneWidget);
    expect(find.text('gw.log'), findsOneWidget);

    // A directory pick fills the field and keeps the overlay open on the
    // directory's own contents instead of ending the completion.
    await tester.tap(find.text('app/'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(pathFieldText(tester), '/logs/app/');
    expect(find.text('archive/'), findsOneWidget);
    expect(find.text('today.log'), findsOneWidget);

    // A file pick completes: field filled, overlay gone.
    await tester.tap(find.text('today.log'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(pathFieldText(tester), '/logs/app/today.log');
    expect(find.text('archive/'), findsNothing);
  });

  testWidgets('a hand-edited path is not clobbered by tab switches', (
    tester,
  ) async {
    final store = makeStore();
    await store.open(
      serverId: 7,
      title: 'A · 网关',
      path: '/logs/gw.log',
      mode: RemoteFileMode.view,
    );
    await store.open(
      serverId: 7,
      title: 'A · 应用',
      path: '/logs/app.log',
      mode: RemoteFileMode.view,
    );

    await tester.pumpWidget(wrap(store));
    await tester.pump();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText != null,
      ),
      '/logs/other.log',
    );

    store.select(0);
    await tester.pump();
    expect(pathFieldText(tester), '/logs/other.log');
  });
}
