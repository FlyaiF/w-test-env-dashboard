enum SshToolKind { terminal, sftp }

enum PasswordMode { argv, clipboard, none }

class ConnectionTarget {
  final String host;
  final int port;
  final String? username;
  final String? password;

  const ConnectionTarget({
    required this.host,
    required this.port,
    this.username,
    this.password,
  });
}

class LaunchResult {
  final bool ok;
  final String? message;
  final bool passwordCopied;

  const LaunchResult({
    required this.ok,
    this.message,
    this.passwordCopied = false,
  });

  factory LaunchResult.failure(String message) =>
      LaunchResult(ok: false, message: message);
}

abstract class SshTool {
  String get id;
  String get displayName;
  SshToolKind get kind;
  Set<PasswordMode> get supportedPasswordModes;
  bool get isAvailableOnPlatform;

  /// Returns the absolute executable path, or null if the tool is not installed.
  /// Implementations should prefer [override] if provided and check default
  /// installation locations otherwise.
  Future<String?> detectExecutable({String? override});

  Future<LaunchResult> launch(
    ConnectionTarget target, {
    required PasswordMode preferredMode,
    String? executableOverride,
  });
}

PasswordMode resolvePasswordMode(SshTool tool, PasswordMode preferred) {
  if (tool.supportedPasswordModes.contains(preferred)) return preferred;
  if (tool.supportedPasswordModes.contains(PasswordMode.clipboard)) {
    return PasswordMode.clipboard;
  }
  return PasswordMode.none;
}
