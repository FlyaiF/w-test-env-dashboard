/// Wire shape of a shared `Database` aggregate as published by the backend Resource
/// Inventory (`DatabaseDto`), fetched from `GET /api/databases`. A faithful mirror of
/// the server contract; the anti-corruption layer resolves it into a display label.
/// The connection block carries only non-secret metadata (no password — brokered).
class DatabaseDto {
  final int id;
  final String? role; // free-text, e.g. business | intermediate
  final String? type; // ORACLE | DAMENG | OCEANBASE | OTHER

  /// Whether the broker holds a login secret for this Database — presence only,
  /// never the secret itself.
  final bool hasSecret;
  final ConnectionInfo? connection;

  const DatabaseDto({
    required this.id,
    this.role,
    this.type,
    this.hasSecret = false,
    this.connection,
  });

  factory DatabaseDto.fromJson(Map<String, dynamic> json) {
    final conn = json['connection'];
    return DatabaseDto(
      id: (json['id'] as num).toInt(),
      role: json['role'] as String?,
      type: json['type'] as String?,
      hasSecret: json['hasSecret'] == true,
      connection: conn is Map<String, dynamic>
          ? ConnectionInfo.fromJson(conn)
          : null,
    );
  }
}

/// Non-secret database connection metadata (no password).
class ConnectionInfo {
  final String? host;
  final int? port;
  final String? serviceName;
  final String? username;

  const ConnectionInfo({this.host, this.port, this.serviceName, this.username});

  factory ConnectionInfo.fromJson(Map<String, dynamic> json) {
    return ConnectionInfo(
      host: json['host'] as String?,
      port: (json['port'] as num?)?.toInt(),
      serviceName: json['serviceName'] as String?,
      username: json['username'] as String?,
    );
  }
}
