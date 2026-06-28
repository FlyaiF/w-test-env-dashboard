import 'dart:convert';
import 'dart:io';

/// Thin-client persisted config. The backend now owns all environment data and
/// database access, so this holds only what Local Desktop Integration needs:
/// defaults and per-tool preferences for launching the user's own SSH/DB tools.
/// Credentials are brokered on demand (slice 06) and never stored here.
class AppConfig {
  SshConfig ssh;
  SshToolsConfig sshTools;
  DbToolsConfig dbTools;

  /// User-set backend base URL (Settings → 后端地址). Null when unset, in which
  /// case the env var / localhost default applies. The env var, if present, wins
  /// over this at startup (see main.dart) — this is the durable fallback.
  String? backendBaseUrl;

  AppConfig({
    required this.ssh,
    required this.sshTools,
    required this.dbTools,
    this.backendBaseUrl,
  });

  factory AppConfig.empty() => AppConfig(
    ssh: SshConfig(defaultUsername: '', defaultPassword: ''),
    sshTools: SshToolsConfig.empty(),
    dbTools: DbToolsConfig.empty(),
  );

  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
    ssh: SshConfig.fromJson(json['ssh'] ?? {}),
    sshTools: SshToolsConfig.fromJson(json['ssh_tools'] ?? {}),
    dbTools: DbToolsConfig.fromJson(json['db_tools'] ?? {}),
    backendBaseUrl: _nullableString((json['backend'] ?? {})['base_url']),
  );

  Map<String, dynamic> toJson() => {
    'ssh': ssh.toJson(),
    'ssh_tools': sshTools.toJson(),
    'db_tools': dbTools.toJson(),
    if (backendBaseUrl != null && backendBaseUrl!.isNotEmpty)
      'backend': {'base_url': backendBaseUrl},
  };

  static String? _nullableString(dynamic v) {
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }
}

class SshConfig {
  String defaultUsername;
  String defaultPassword;

  SshConfig({required this.defaultUsername, required this.defaultPassword});

  factory SshConfig.fromJson(Map<String, dynamic> json) => SshConfig(
    defaultUsername: json['default_username'] ?? '',
    defaultPassword: json['default_password'] ?? '',
  );

  Map<String, dynamic> toJson() => {
    'default_username': defaultUsername,
    'default_password': defaultPassword,
  };
}

class SshToolsConfig {
  String? defaultTerminalToolId;
  String? defaultSftpToolId;
  Map<String, String> executablePaths;
  String passwordMode; // 'argv' | 'clipboard'

  SshToolsConfig({
    this.defaultTerminalToolId,
    this.defaultSftpToolId,
    Map<String, String>? executablePaths,
    this.passwordMode = 'argv',
  }) : executablePaths = executablePaths ?? {};

  factory SshToolsConfig.empty() => SshToolsConfig();

  factory SshToolsConfig.fromJson(Map<String, dynamic> json) {
    final raw = json['executable_paths'];
    final paths = <String, String>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        final v = entry.value;
        if (v is String && v.isNotEmpty) {
          paths[entry.key.toString()] = v;
        }
      }
    }
    return SshToolsConfig(
      defaultTerminalToolId: _nullableString(json['default_terminal_tool_id']),
      defaultSftpToolId: _nullableString(json['default_sftp_tool_id']),
      executablePaths: paths,
      passwordMode: (json['password_mode'] as String?) ?? 'argv',
    );
  }

  Map<String, dynamic> toJson() => {
    if (defaultTerminalToolId != null)
      'default_terminal_tool_id': defaultTerminalToolId,
    if (defaultSftpToolId != null) 'default_sftp_tool_id': defaultSftpToolId,
    'executable_paths': executablePaths,
    'password_mode': passwordMode,
  };

  static String? _nullableString(dynamic v) {
    if (v is String && v.isNotEmpty) return v;
    return null;
  }
}

/// Per-tool preferences for launching the user's own DB tools. Mirrors
/// [SshToolsConfig] and the `DbToolRegistry`; kept in its own `db_tools` section
/// rather than overloading `ssh_tools` so the persisted schema stays symmetric.
class DbToolsConfig {
  String? defaultToolId;
  Map<String, String> executablePaths;

  DbToolsConfig({this.defaultToolId, Map<String, String>? executablePaths})
    : executablePaths = executablePaths ?? {};

  factory DbToolsConfig.empty() => DbToolsConfig();

  factory DbToolsConfig.fromJson(Map<String, dynamic> json) {
    final raw = json['executable_paths'];
    final paths = <String, String>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        final v = entry.value;
        if (v is String && v.isNotEmpty) {
          paths[entry.key.toString()] = v;
        }
      }
    }
    return DbToolsConfig(
      defaultToolId: SshToolsConfig._nullableString(json['default_tool_id']),
      executablePaths: paths,
    );
  }

  Map<String, dynamic> toJson() => {
    if (defaultToolId != null) 'default_tool_id': defaultToolId,
    'executable_paths': executablePaths,
  };
}

class ConfigService {
  static const _dirName = '.test-env-dashboard';
  static const _fileName = 'config.json';

  static Future<File> _configFile() async {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    final dir = Directory('$home/$_dirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/$_fileName');
  }

  static Future<AppConfig> load() async {
    try {
      final file = await _configFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        return AppConfig.fromJson(jsonDecode(content));
      }
    } catch (_) {}
    return AppConfig.empty();
  }

  static Future<void> save(AppConfig config) async {
    final file = await _configFile();
    final encoder = const JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(config.toJson()));
  }
}
