import 'dart:io';

import '../db_tool.dart';
import 'dbeaver_connection.dart';

/// Launches the user's own DBeaver, fed brokered credentials (ADR-0005). The
/// connection is opened transiently (`save=false`); the dashboard ships no DB
/// drivers and has no in-app browser — DBeaver is the first-class path.
///
/// Note on the secret: DBeaver's only CLI entry point is the `-con` spec, so the
/// brokered password is passed on the process argv (briefly visible in the local
/// process table). This is the same exposure class as the SSH tools' default
/// `PasswordMode.argv`, and is accepted for the same reason — a single-user
/// desktop launching a session against its own credentials. The secret is held
/// only for this launch and never written to disk.
class DbeaverTool extends DbTool {
  @override
  String get id => 'dbeaver';

  @override
  String get displayName => 'DBeaver';

  @override
  bool get isAvailableOnPlatform => true; // cross-platform

  static const _windowsCandidates = [
    r'C:\Program Files\DBeaver\dbeaver.exe',
    r'C:\Program Files (x86)\DBeaver\dbeaver.exe',
  ];

  static const _macosCandidates = [
    '/Applications/DBeaver.app/Contents/MacOS/dbeaver',
  ];

  static const _linuxCandidates = [
    '/usr/bin/dbeaver',
    '/usr/share/dbeaver/dbeaver',
    '/opt/dbeaver/dbeaver',
    '/snap/bin/dbeaver-ce',
  ];

  @override
  Future<String?> detectExecutable({String? override}) async {
    if (override != null && override.trim().isNotEmpty) {
      final p = override.trim();
      if (await File(p).exists()) return p;
    }
    for (final p in _candidatesForPlatform()) {
      if (await File(p).exists()) return p;
    }
    return null;
  }

  static List<String> _candidatesForPlatform() {
    if (Platform.isWindows) return _windowsCandidates;
    if (Platform.isMacOS) return _macosCandidates;
    return _linuxCandidates;
  }

  @override
  Future<LaunchResult> launch(
    DbConnectionTarget target, {
    String? executableOverride,
  }) async {
    final exe = await detectExecutable(override: executableOverride);
    if (exe == null) {
      return LaunchResult.failure('未找到 DBeaver，请在设置中指定可执行文件路径');
    }
    final spec = buildDbeaverConnectionSpec(target);
    try {
      await Process.start(exe, [
        '-con',
        spec,
      ], mode: ProcessStartMode.detached);
    } catch (e) {
      return LaunchResult.failure('启动 DBeaver 失败: $e');
    }
    return const LaunchResult(ok: true, message: '已在 DBeaver 中打开');
  }
}
