import '../ssh_tools/ssh_tool.dart' show LaunchResult;

export '../ssh_tools/ssh_tool.dart' show LaunchResult;

/// What a DB tool needs to open a connection. Built from a brokered
/// [DatabaseCredential] (ADR-0005) just before launch and never persisted.
/// [jdbcUrl] is the backend's ready-to-use connect string when available;
/// otherwise the discrete host/port/database fields are used.
class DbConnectionTarget {
  final String? type; // ORACLE | DAMENG | OCEANBASE | OTHER
  final String? host;
  final int? port;
  final String? database;
  final String? username;
  final String? password;
  final String? jdbcUrl;

  /// Optional display name for the launched connection.
  final String? name;

  const DbConnectionTarget({
    this.type,
    this.host,
    this.port,
    this.database,
    this.username,
    this.password,
    this.jdbcUrl,
    this.name,
  });
}

/// A launchable external database tool (e.g. DBeaver). Mirrors [SshTool]:
/// adding a tool is one class plus a [DbToolRegistry] entry. The dashboard
/// feeds it brokered credentials and never stores them.
abstract class DbTool {
  String get id;
  String get displayName;
  bool get isAvailableOnPlatform;

  /// Whether this tool can open a database of [type] (`ORACLE` | `DAMENG` |
  /// `OCEANBASE` | `OTHER` | null). Engine-specific tools (e.g. PL/SQL
  /// Developer) narrow this; the default is engine-agnostic.
  bool supportsType(String? type) => true;

  /// Absolute executable path, or null if the tool is not installed. Prefers
  /// [override] when provided, else checks default install locations.
  Future<String?> detectExecutable({String? override});

  Future<LaunchResult> launch(
    DbConnectionTarget target, {
    String? executableOverride,
  });
}
