import 'package:env_viewer/api/backend_client.dart';
import 'package:env_viewer/pages/catalog/component_access.dart';
import 'package:env_viewer/services/access/access_launcher.dart';
import 'package:env_viewer/services/db_tools/db_tool.dart';
import 'package:env_viewer/services/ssh_tools/ssh_tool.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the brokered launches it is asked to perform instead of touching the
/// backend, so the option builders can be asserted in isolation.
class _FakeLauncher extends AccessLauncher {
  final List<
    ({int serverId, SshTool tool, PasswordMode mode, String? override})
  >
  sshCalls = [];
  final List<({int databaseId, DbTool tool, String? name, String? override})>
  dbCalls = [];

  _FakeLauncher() : super(BackendClient());

  @override
  Future<LaunchResult> launchSsh(
    int serverId,
    SshTool tool, {
    required PasswordMode preferredMode,
    String? executableOverride,
    String? startPath,
  }) async {
    sshCalls.add((
      serverId: serverId,
      tool: tool,
      mode: preferredMode,
      override: executableOverride,
    ));
    return const LaunchResult(ok: true, message: 'ssh');
  }

  @override
  Future<LaunchResult> launchDb(
    int databaseId,
    DbTool tool, {
    String? executableOverride,
    String? name,
  }) async {
    dbCalls.add((
      databaseId: databaseId,
      tool: tool,
      name: name,
      override: executableOverride,
    ));
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

  /// When set, the tool only supports databases of this engine type.
  final String? supportedType;

  _FakeDbTool(this.id, this.displayName, {this.supportedType});

  @override
  bool supportsType(String? type) =>
      supportedType == null || type == supportedType;

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

    test('a configured executable path is passed through as the override', () async {
      final launcher = _FakeLauncher();
      final tool = _FakeSshTool('a', 'Xshell');

      await sshLaunchOptions(
        launcher,
        7,
        tools: [tool],
        executablePaths: {'a': '/opt/Xshell'},
      ).single.run();

      expect(launcher.sshCalls.single.override, '/opt/Xshell');
    });

    test('the preferred tool is ordered first', () {
      final options = sshLaunchOptions(
        _FakeLauncher(),
        7,
        tools: [_FakeSshTool('a', 'Xshell'), _FakeSshTool('b', 'Terminal')],
        preferredToolId: 'b',
      );
      expect(options.map((o) => o.label), ['Terminal', 'Xshell']);
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

    test('several databases group the options instead of qualifying labels', () async {
      final launcher = _FakeLauncher();
      final tools = [_FakeDbTool('dbeaver', 'DBeaver')];

      final options = dbLaunchOptions(launcher, [9, 12], tools: tools);

      expect(options.map((o) => o.label), ['DBeaver', 'DBeaver']);
      expect(options.map((o) => o.group), ['#9', '#12']);
      await options[1].run();
      expect(launcher.dbCalls.single.databaseId, 12);
    });

    test('resolved labels name the multi-db groups instead of #id', () {
      final options = dbLaunchOptions(
        _FakeLauncher(),
        [9, 12],
        tools: [_FakeDbTool('dbeaver', 'DBeaver')],
        databaseLabels: {9: '业务库 10.20.155.175', 12: '中转库 10.20.155.180'},
      );

      expect(options.map((o) => o.group), [
        '业务库 10.20.155.175',
        '中转库 10.20.155.180',
      ]);
      // A single database keeps a flat, ungrouped menu.
      expect(
        dbLaunchOptions(
          _FakeLauncher(),
          [9],
          tools: [_FakeDbTool('dbeaver', 'DBeaver')],
        ).single.group,
        isNull,
      );
    });

    test('engine-specific tools are filtered out per database type', () {
      final oracleOnly = _FakeDbTool('plsqldev', 'PL/SQL Developer',
          supportedType: 'ORACLE');
      final generic = _FakeDbTool('dbeaver', 'DBeaver');

      final options = dbLaunchOptions(
        _FakeLauncher(),
        [9, 12],
        tools: [generic, oracleOnly],
        databaseTypes: {9: 'ORACLE', 12: 'DAMENG'},
      );

      expect(
        options.map((o) => '${o.group}:${o.label}'),
        ['#9:DBeaver', '#9:PL/SQL Developer', '#12:DBeaver'],
      );
    });

    test('without type information every tool stays listed', () {
      final oracleOnly = _FakeDbTool('plsqldev', 'PL/SQL Developer',
          supportedType: 'ORACLE');

      final options = dbLaunchOptions(
        _FakeLauncher(),
        [9],
        tools: [oracleOnly],
      );

      expect(options.map((o) => o.label), ['PL/SQL Developer']);
    });

    test('a configured executable path is passed through as the override', () async {
      final launcher = _FakeLauncher();

      await dbLaunchOptions(
        launcher,
        [9],
        tools: [_FakeDbTool('dbeaver', 'DBeaver')],
        executablePaths: {'dbeaver': '/opt/dbeaver'},
      ).single.run();

      expect(launcher.dbCalls.single.override, '/opt/dbeaver');
    });
  });
}
