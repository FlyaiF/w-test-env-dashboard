import 'package:env_viewer/api/backend_client.dart';
import 'package:env_viewer/pages/catalog/component_access.dart';
import 'package:env_viewer/services/access/access_launcher.dart';
import 'package:env_viewer/services/db_tools/db_tool.dart';
import 'package:env_viewer/services/ssh_tools/ssh_tool.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the brokered launches it is asked to perform instead of touching the
/// backend, so the option builders can be asserted in isolation.
class _FakeLauncher extends AccessLauncher {
  final List<({int serverId, SshTool tool, PasswordMode mode})> sshCalls = [];
  final List<({int databaseId, DbTool tool, String? name})> dbCalls = [];

  _FakeLauncher() : super(BackendClient());

  @override
  Future<LaunchResult> launchSsh(
    int serverId,
    SshTool tool, {
    required PasswordMode preferredMode,
    String? executableOverride,
    String? startPath,
  }) async {
    sshCalls.add((serverId: serverId, tool: tool, mode: preferredMode));
    return const LaunchResult(ok: true, message: 'ssh');
  }

  @override
  Future<LaunchResult> launchDb(
    int databaseId,
    DbTool tool, {
    String? executableOverride,
    String? name,
  }) async {
    dbCalls.add((databaseId: databaseId, tool: tool, name: name));
    return const LaunchResult(ok: true, message: 'db');
  }
}

class _FakeSshTool extends SshTool {
  @override
  final String id;
  @override
  final String displayName;

  _FakeSshTool(this.id, this.displayName);

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
  }) async => const LaunchResult(ok: true);
}

class _FakeDbTool extends DbTool {
  @override
  final String id;
  @override
  final String displayName;

  _FakeDbTool(this.id, this.displayName);

  @override
  bool get isAvailableOnPlatform => true;

  @override
  Future<String?> detectExecutable({String? override}) async => '/fake';

  @override
  Future<LaunchResult> launch(
    DbConnectionTarget target, {
    String? executableOverride,
  }) async => const LaunchResult(ok: true);
}

void main() {
  group('sshLaunchOptions', () {
    test('one option per tool, labelled by display name', () {
      final launcher = _FakeLauncher();
      final tools = [_FakeSshTool('a', 'Xshell'), _FakeSshTool('b', 'Terminal')];

      final options = sshLaunchOptions(launcher, 7, tools: tools);

      expect(options.map((o) => o.label), ['Xshell', 'Terminal']);
    });

    test('running an option brokers the right server with that tool', () async {
      final launcher = _FakeLauncher();
      final tool = _FakeSshTool('a', 'Xshell');

      await sshLaunchOptions(launcher, 7, tools: [tool]).single.run();

      expect(launcher.sshCalls, hasLength(1));
      expect(launcher.sshCalls.single.serverId, 7);
      expect(launcher.sshCalls.single.tool, same(tool));
      expect(launcher.sshCalls.single.mode, PasswordMode.argv);
    });

    test('no installed tools yields no options', () {
      expect(sshLaunchOptions(_FakeLauncher(), 7, tools: const []), isEmpty);
    });
  });

  group('dbLaunchOptions', () {
    test('single database labels by tool name and routes to that database', () async {
      final launcher = _FakeLauncher();
      final tool = _FakeDbTool('dbeaver', 'DBeaver');

      final options = dbLaunchOptions(
        launcher,
        [9],
        tools: [tool],
        connectionName: 'env · gateway',
      );

      expect(options.map((o) => o.label), ['DBeaver']);
      await options.single.run();
      expect(launcher.dbCalls.single.databaseId, 9);
      expect(launcher.dbCalls.single.name, 'env · gateway');
    });

    test('several databases produce a qualified cross product', () async {
      final launcher = _FakeLauncher();
      final tools = [_FakeDbTool('dbeaver', 'DBeaver')];

      final options = dbLaunchOptions(launcher, [9, 12], tools: tools);

      expect(options.map((o) => o.label), ['#9 · DBeaver', '#12 · DBeaver']);
      await options[1].run();
      expect(launcher.dbCalls.single.databaseId, 12);
    });
  });
}
