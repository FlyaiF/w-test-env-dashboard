import 'dart:io';

import 'package:flutter/services.dart';

import '../ssh_tool.dart';

class MacosTerminalTool extends SshTool {
  @override
  String get id => 'macos_terminal';

  @override
  String get displayName => 'macOS 终端';

  @override
  SshToolKind get kind => SshToolKind.terminal;

  @override
  Set<PasswordMode> get supportedPasswordModes => const {
    PasswordMode.clipboard,
    PasswordMode.none,
  };

  @override
  bool get isAvailableOnPlatform => Platform.isMacOS;

  @override
  Future<String?> detectExecutable({String? override}) async {
    if (override != null && override.trim().isNotEmpty) {
      final p = override.trim();
      if (await File(p).exists()) return p;
    }
    const osascript = '/usr/bin/osascript';
    if (await File(osascript).exists()) return osascript;
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
      return LaunchResult.failure('未找到 osascript');
    }
    final mode = resolvePasswordMode(this, preferredMode);

    final user = target.username;
    final hostPart = (user != null && user.isNotEmpty)
        ? '$user@${target.host}'
        : target.host;
    final hasStartPath =
        target.startPath != null && target.startPath!.trim().isNotEmpty;
    final rawSshCmd = hasStartPath
        ? _buildSshWithStartPath(hostPart, target.port, target.startPath!)
        : 'ssh -p ${target.port} $hostPart';
    final script =
        'tell application "Terminal" to do script "${_escapeAppleScript(rawSshCmd)}"';

    var passwordCopied = false;
    if (mode == PasswordMode.clipboard &&
        target.password != null &&
        target.password!.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: target.password!));
      passwordCopied = true;
    }

    try {
      await Process.start(exe, [
        '-e',
        script,
        '-e',
        'tell application "Terminal" to activate',
      ], mode: ProcessStartMode.detached);
    } catch (e) {
      return LaunchResult.failure('启动终端失败: $e');
    }

    return LaunchResult(
      ok: true,
      passwordCopied: passwordCopied,
      message: passwordCopied ? '密码已复制，请在 Terminal 中粘贴' : '已在终端中打开',
    );
  }

  static String _escapeAppleScript(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  /// Wraps [s] in a bash single-quoted argument, escaping any embedded
  /// single quotes via the `'\''` idiom.
  static String _bashSingleQuote(String s) =>
      "'${s.replaceAll("'", r"'\''")}'";

  static String _buildSshWithStartPath(
    String hostPart,
    int port,
    String startPath,
  ) {
    final remoteCmd = 'cd ${_bashSingleQuote(startPath)}; exec \$SHELL -l';
    final localArg = _bashSingleQuote(remoteCmd);
    return 'ssh -t -p $port $hostPart $localArg';
  }
}
