import 'dart:io';

import '../ssh_tool.dart';
import 'netsarang_url.dart';

class XftpTool extends SshTool {
  @override
  String get id => 'xftp';

  @override
  String get displayName => 'Xftp';

  @override
  SshToolKind get kind => SshToolKind.sftp;

  @override
  Set<PasswordMode> get supportedPasswordModes => const {
    PasswordMode.argv,
    PasswordMode.none,
  };

  @override
  bool get isAvailableOnPlatform => Platform.isWindows;

  static const _candidates = [
    r'C:\Program Files\NetSarang\Xftp 8\Xftp.exe',
    r'C:\Program Files\NetSarang\Xftp 7\Xftp.exe',
    r'C:\Program Files (x86)\NetSarang\Xftp 8\Xftp.exe',
    r'C:\Program Files (x86)\NetSarang\Xftp 7\Xftp.exe',
    r'C:\Program Files (x86)\NetSarang\Xftp 6\Xftp.exe',
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
      return LaunchResult.failure('未找到 Xftp，请在设置中指定可执行文件路径');
    }
    final mode = resolvePasswordMode(this, preferredMode);
    final urlTarget = mode == PasswordMode.argv
        ? target
        : ConnectionTarget(
            host: target.host,
            port: target.port,
            username: target.username,
            startPath: target.startPath,
          );
    final url = buildNetsarangUrl('sftp', urlTarget, includeStartPath: true);
    try {
      await Process.start(exe, [
        '-url',
        url,
      ], mode: ProcessStartMode.detached);
    } catch (e) {
      return LaunchResult.failure('启动 Xftp 失败: $e');
    }
    return LaunchResult(
      ok: true,
      message: mode == PasswordMode.argv
          ? '已在 Xftp 中打开'
          : '已在 Xftp 中打开（未传递密码）',
    );
  }
}
