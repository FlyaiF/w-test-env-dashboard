import 'dart:convert';

import 'package:env_viewer/api/backend_client.dart';
import 'package:env_viewer/remote_files/remote_file_store.dart';
import 'package:env_viewer/services/remote_file/remote_file_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Session that records instead of dialing SSH.
class _FakeSession extends RemoteFileSession {
  int connectCalls = 0;
  bool disposed = false;

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
  Future<void> connect() async {
    connectCalls++;
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  BackendClient clientWith(Map<String, dynamic> credential) {
    return BackendClient(
      baseUrl: 'http://test',
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/servers/7/credentials') {
          return http.Response(
            jsonEncode(credential),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{}', 404);
      }),
    );
  }

  RemoteFileStore storeWith(
    BackendClient client,
    List<_FakeSession> created,
  ) {
    return RemoteFileStore(
      client,
      sessionFactory: (spec) {
        final session = _FakeSession(spec);
        created.add(session);
        return session;
      },
    );
  }

  test('opens a tab with brokered credentials and starts the session', () async {
    final created = <_FakeSession>[];
    final store = storeWith(
      clientWith({
        'serverId': 7,
        'host': '10.0.0.5',
        'port': 2222,
        'username': 'app',
        'secret': 's3cret',
      }),
      created,
    );

    final outcome = await store.open(
      serverId: 7,
      title: '联调A · 网关',
      path: '/logs/gw.log',
      mode: RemoteFileMode.follow,
      jumpToPage: true,
    );

    expect(outcome, isA<RemoteOpenOk>());
    expect(store.tabs, hasLength(1));
    expect(store.jumpSignal, 1);
    final session = created.single;
    expect(session.connectCalls, 1);
    expect(session.host, '10.0.0.5');
    expect(session.port, 2222);
    expect(session.username, 'app');
    expect(session.path, '/logs/gw.log');
  });

  test('a missing stored secret asks the caller for one', () async {
    final created = <_FakeSession>[];
    final store = storeWith(
      clientWith({
        'serverId': 7,
        'host': '10.0.0.5',
        'port': null,
        'username': 'app',
        'secret': null,
      }),
      created,
    );

    final outcome = await store.open(
      serverId: 7,
      title: 't',
      path: '/logs/gw.log',
      mode: RemoteFileMode.follow,
    );

    expect(outcome, isA<RemoteOpenNeedsSecret>());
    final needs = outcome as RemoteOpenNeedsSecret;
    expect(needs.host, '10.0.0.5');
    expect(needs.port, 22);
    expect(needs.username, 'app');
    expect(store.tabs, isEmpty);
    expect(created, isEmpty);

    // Retry with the collected credential succeeds and uses the overrides.
    final retried = await store.open(
      serverId: 7,
      title: 't',
      path: '/logs/gw.log',
      mode: RemoteFileMode.follow,
      usernameOverride: 'root',
      secretOverride: 'typed',
    );
    expect(retried, isA<RemoteOpenOk>());
    expect(created.single.username, 'root');
  });

  test('an already-open file is focused, not duplicated', () async {
    final created = <_FakeSession>[];
    final store = storeWith(
      clientWith({
        'serverId': 7,
        'host': 'h',
        'port': 22,
        'username': 'u',
        'secret': 's',
      }),
      created,
    );

    await store.open(
      serverId: 7,
      title: 'a',
      path: '/logs/a.log',
      mode: RemoteFileMode.follow,
    );
    await store.open(
      serverId: 7,
      title: 'b',
      path: '/logs/b.log',
      mode: RemoteFileMode.follow,
    );
    expect(store.activeIndex, 1);

    final outcome = await store.open(
      serverId: 7,
      title: 'a',
      path: '/logs/a.log',
      mode: RemoteFileMode.follow,
    );
    expect(outcome, isA<RemoteOpenOk>());
    expect(store.tabs, hasLength(2));
    expect(store.activeIndex, 0);
    expect(created, hasLength(2));
  });

  test('the same path in a different mode is a separate tab', () async {
    final created = <_FakeSession>[];
    final store = storeWith(
      clientWith({
        'serverId': 7,
        'host': 'h',
        'port': 22,
        'username': 'u',
        'secret': 's',
      }),
      created,
    );

    await store.open(
      serverId: 7,
      title: 'a',
      path: '/etc/app.conf',
      mode: RemoteFileMode.follow,
    );
    await store.open(
      serverId: 7,
      title: 'a',
      path: '/etc/app.conf',
      mode: RemoteFileMode.view,
    );
    expect(store.tabs, hasLength(2));
  });

  test('a server without a host address fails with a clear message', () async {
    final store = storeWith(
      clientWith({'serverId': 7, 'host': null, 'secret': 's'}),
      [],
    );

    final outcome = await store.open(
      serverId: 7,
      title: 't',
      path: '/x',
      mode: RemoteFileMode.view,
    );
    expect(outcome, isA<RemoteOpenFailed>());
    expect((outcome as RemoteOpenFailed).message, contains('主机地址'));
  });

  test('a broker failure surfaces the backend message', () async {
    final client = BackendClient(
      baseUrl: 'http://test',
      httpClient: MockClient(
        (_) async => http.Response.bytes(
          utf8.encode(jsonEncode({'detail': '服务器不存在'})),
          404,
          headers: {'content-type': 'application/problem+json'},
        ),
      ),
    );
    final store = storeWith(client, []);

    final outcome = await store.open(
      serverId: 7,
      title: 't',
      path: '/x',
      mode: RemoteFileMode.view,
    );
    expect(outcome, isA<RemoteOpenFailed>());
    expect((outcome as RemoteOpenFailed).message, contains('服务器不存在'));
  });

  test('closing a tab disposes its session and keeps a valid active index',
      () async {
    final created = <_FakeSession>[];
    final store = storeWith(
      clientWith({
        'serverId': 7,
        'host': 'h',
        'port': 22,
        'username': 'u',
        'secret': 's',
      }),
      created,
    );

    await store.open(
      serverId: 7, title: 'a', path: '/a', mode: RemoteFileMode.follow);
    await store.open(
      serverId: 7, title: 'b', path: '/b', mode: RemoteFileMode.follow);
    await store.open(
      serverId: 7, title: 'c', path: '/c', mode: RemoteFileMode.follow);
    expect(store.activeIndex, 2);

    store.close(2);
    expect(created[2].disposed, isTrue);
    expect(store.activeIndex, 1);

    store.close(0);
    expect(store.activeIndex, 0);
    expect(store.tabs.single.title, 'b');
  });
}
