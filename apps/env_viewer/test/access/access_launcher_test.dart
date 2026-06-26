import 'dart:convert';

import 'package:env_viewer/api/backend_client.dart';
import 'package:env_viewer/services/access/access_launcher.dart';
import 'package:env_viewer/services/db_tools/db_tool.dart';
import 'package:env_viewer/services/ssh_tools/ssh_tool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Records the target it is asked to launch instead of spawning a process, so
/// the brokering -> launch flow can be asserted without a real DB tool.
class _RecordingDbTool extends DbTool {
  DbConnectionTarget? launched;

  @override
  String get id => 'recording';

  @override
  String get displayName => 'Recording';

  @override
  bool get isAvailableOnPlatform => true;

  @override
  Future<String?> detectExecutable({String? override}) async => '/fake';

  @override
  Future<LaunchResult> launch(
    DbConnectionTarget target, {
    String? executableOverride,
  }) async {
    launched = target;
    return const LaunchResult(ok: true, message: 'ok');
  }
}

class _RecordingSshTool extends SshTool {
  ConnectionTarget? launched;

  @override
  String get id => 'recording-ssh';

  @override
  String get displayName => 'Recording SSH';

  @override
  SshToolKind get kind => SshToolKind.terminal;

  @override
  Set<PasswordMode> get supportedPasswordModes => const {PasswordMode.argv};

  @override
  bool get isAvailableOnPlatform => true;

  @override
  Future<String?> detectExecutable({String? override}) async => '/fake';

  @override
  Future<LaunchResult> launch(
    ConnectionTarget target, {
    required PasswordMode preferredMode,
    String? executableOverride,
  }) async {
    launched = target;
    return const LaunchResult(ok: true, message: 'ok');
  }
}

void main() {
  group('AccessLauncher', () {
    test('feeds brokered DB credentials into the tool launch', () async {
      final backend = BackendClient(
        baseUrl: 'http://example.test:8080',
        httpClient: MockClient((req) async {
          expect(req.url.path, '/api/databases/9/credentials');
          return http.Response(
            jsonEncode({
              'databaseId': 9,
              'type': 'ORACLE',
              'host': '10.0.2.5',
              'port': 1521,
              'serviceName': 'ORCL',
              'username': 'app',
              'jdbcUrl': 'jdbc:oracle:thin:@//10.0.2.5:1521/ORCL',
              'secret': 'db-pw',
            }),
            200,
          );
        }),
      );
      final tool = _RecordingDbTool();

      final result = await AccessLauncher(backend).launchDb(9, tool);

      expect(result.ok, isTrue);
      expect(tool.launched, isNotNull);
      expect(tool.launched!.password, 'db-pw');
      expect(tool.launched!.jdbcUrl, 'jdbc:oracle:thin:@//10.0.2.5:1521/ORCL');
    });

    test('feeds brokered SSH credentials into the tool launch', () async {
      final backend = BackendClient(
        baseUrl: 'http://example.test:8080',
        httpClient: MockClient((req) async {
          expect(req.url.path, '/api/servers/5/credentials');
          return http.Response(
            jsonEncode({
              'serverId': 5,
              'host': '10.0.0.1',
              'port': 22,
              'username': 'deploy',
              'secret': 's3cr3t',
            }),
            200,
          );
        }),
      );
      final tool = _RecordingSshTool();

      final result = await AccessLauncher(backend).launchSsh(
        5,
        tool,
        preferredMode: PasswordMode.argv,
      );

      expect(result.ok, isTrue);
      expect(tool.launched!.password, 's3cr3t');
      expect(tool.launched!.username, 'deploy');
    });

    test('a backend failure becomes a failed launch, not an exception', () async {
      final backend = BackendClient(
        baseUrl: 'http://example.test:8080',
        httpClient: MockClient((req) async => http.Response('nope', 404)),
      );
      final tool = _RecordingDbTool();

      final result = await AccessLauncher(backend).launchDb(9, tool);

      expect(result.ok, isFalse);
      expect(result.message, contains('404'));
      expect(tool.launched, isNull); // never reached the tool
    });
  });
}
