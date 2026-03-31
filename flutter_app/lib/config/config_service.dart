import 'dart:convert';
import 'dart:io';

class AppConfig {
  OracleConfig oracle;
  SshConfig ssh;

  AppConfig({required this.oracle, required this.ssh});

  factory AppConfig.empty() => AppConfig(
    oracle: OracleConfig(
      host: '',
      port: 1521,
      service: '',
      username: '',
      password: '',
    ),
    ssh: SshConfig(defaultUsername: '', defaultPassword: ''),
  );

  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
    oracle: OracleConfig.fromJson(json['oracle'] ?? {}),
    ssh: SshConfig.fromJson(json['ssh'] ?? {}),
  );

  Map<String, dynamic> toJson() => {
    'oracle': oracle.toJson(),
    'ssh': ssh.toJson(),
  };

  String get dsn =>
      'oracle://${oracle.username}:${oracle.password}@${oracle.host}:${oracle.port}/${oracle.service}';

  bool get isOracleConfigured =>
      oracle.host.isNotEmpty &&
      oracle.service.isNotEmpty &&
      oracle.username.isNotEmpty;
}

class OracleConfig {
  String host;
  int port;
  String service;
  String username;
  String password;

  OracleConfig({
    required this.host,
    required this.port,
    required this.service,
    required this.username,
    required this.password,
  });

  factory OracleConfig.fromJson(Map<String, dynamic> json) => OracleConfig(
    host: json['host'] ?? '',
    port: json['port'] ?? 1521,
    service: json['service'] ?? '',
    username: json['username'] ?? '',
    password: json['password'] ?? '',
  );

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'service': service,
    'username': username,
    'password': password,
  };
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
