import 'dart:io';

import '../ssh_tool.dart';
import 'netsarang_url.dart';

class XshellTool extends SshTool {
  @override
  String get id => 'xshell';

  @override
  String get displayName => 'Xshell';

  @override
  SshToolKind get kind => SshToolKind.terminal;

  @override
  Set<PasswordMode> get supportedPasswordModes => const {
    PasswordMode.argv,
    PasswordMode.none,
  };

  @override
  bool get isAvailableOnPlatform => Platform.isWindows;

  static const _candidates = [
    r'C:\Program Files\NetSarang\Xshell 8\Xshell.exe',
    r'C:\Program Files\NetSarang\Xshell 7\Xshell.exe',
    r'C:\Program Files (x86)\NetSarang\Xshell 8\Xshell.exe',
    r'C:\Program Files (x86)\NetSarang\Xshell 7\Xshell.exe',
    r'C:\Program Files (x86)\NetSarang\Xshell 6\Xshell.exe',
  ];

  @override
  Future<String?> detectExecutable({String? override}) async {
    if (override != null && override.trim().isNotEmpty) {
      final p = override.trim();
      if (await File(p).exists()) return p;
    }
    for (final p in _candidates) {
      if (await File(p).exists()) return p;
    }
    return null;
  }

  @override
  Future<LaunchResult> launch(
    ConnectionTarget target, {
    required PasswordMode preferredMode,
    String? executableOverride,
  }) async {
    final exe = await detectExecutable(override: executableOverride);
    if (exe == null) {
      return LaunchResult.failure('未找到 Xshell，请在设置中指定可执行文件路径');
    }
    final mode = resolvePasswordMode(this, preferredMode);
    final urlTarget = mode == PasswordMode.argv
        ? target
        : ConnectionTarget(
            host: target.host,
            port: target.port,
            username: target.username,
          );
    final url = buildNetsarangUrl('ssh', urlTarget);
    try {
      await Process.start(exe, [
        '-url',
        url,
      ], mode: ProcessStartMode.detached);
    } catch (e) {
      return LaunchResult.failure('启动 Xshell 失败: $e');
    }
    return LaunchResult(
      ok: true,
      message: mode == PasswordMode.argv
          ? '已在 Xshell 中打开'
          : '已在 Xshell 中打开（未传递密码）',
    );
  }
}
