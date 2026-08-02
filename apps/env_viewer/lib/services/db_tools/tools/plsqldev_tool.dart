import 'dart:io';

import '../db_tool.dart';
import 'plsqldev_connection.dart';

/// Launches the user's own PL/SQL Developer against an Oracle database, fed
/// brokered credentials (ADR-0005). Oracle-only by nature — [supportsType]
/// keeps it out of the menu for Dameng/OceanBase targets.
///
/// PL/SQL Developer is Windows software; install directories are versioned
/// (`C:\Program Files\PLSQL Developer 15\...`), so detection scans Program
/// Files for `PLSQL Developer*` rather than pinning versions. On other
/// platforms the tool stays listed (same policy as DBeaver) so a
/// CrossOver/Wine wrapper can be configured as the executable path in 设置.
///
/// The secret rides the `userid=` argv (briefly visible in the local process
/// table) — the same exposure class as DBeaver's `-con` spec and the SSH
/// tools' `PasswordMode.argv`, accepted for the same single-user-desktop
/// reason. Held only for this launch, never written to disk.
class PlsqldevTool extends DbTool {
  @override
  String get id => 'plsqldev';

  @override
  String get displayName => 'PL/SQL Developer';

  @override
  bool get isAvailableOnPlatform => true;

  @override
  bool supportsType(String? type) => type == 'ORACLE';

  @override
  Future<String?> detectExecutable({String? override}) async {
    if (override != null && override.trim().isNotEmpty) {
      final p = override.trim();
      if (await File(p).exists()) return p;
    }
    if (!Platform.isWindows) return null;
    final candidates = <String>[];
    final roots = [
      Platform.environment['ProgramFiles'],
      Platform.environment['ProgramFiles(x86)'],
    ];
    for (final root in roots) {
      if (root == null || root.isEmpty) continue;
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      await for (final entry in dir.list(followLinks: false)) {
        if (entry is! Directory) continue;
        final name = entry.uri.pathSegments
            .lastWhere((s) => s.isNotEmpty, orElse: () => '')
            .toLowerCase();
        if (name.startsWith('plsql developer')) {
          candidates.add('${entry.path}\\plsqldev.exe');
        }
      }
    }
    // Versioned folder names sort ascending; prefer the newest install.
    candidates.sort((a, b) => b.compareTo(a));
    for (final p in candidates) {
      if (await File(p).exists()) return p;
    }
    return null;
  }

  @override
  Future<LaunchResult> launch(
    DbConnectionTarget target, {
    String? executableOverride,
  }) async {
    final exe = await detectExecutable(override: executableOverride);
    if (exe == null) {
      return LaunchResult.failure('未找到 PL/SQL Developer，请在设置中指定可执行文件路径');
    }
    final userid = buildPlsqldevUserid(target);
    if (userid == null) {
      return LaunchResult.failure('该数据库缺少主机或用户名，无法生成 PL/SQL Developer 登录参数');
    }
    try {
      await Process.start(exe, [
        'userid=$userid',
      ], mode: ProcessStartMode.detached);
    } catch (e) {
      return LaunchResult.failure('启动 PL/SQL Developer 失败: $e');
    }
    return const LaunchResult(ok: true, message: '已在 PL/SQL Developer 中打开');
  }
}
