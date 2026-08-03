/// Wire shape of a brokered DB credential bundle for a Database
/// (`DatabaseCredentialDto`). Fetched on demand just before launching the
/// user's own DB tool and discarded after — nothing is persisted client-side
/// (ADR-0005). [jdbcUrl] is a ready-to-use connect string, or null for an
/// engine the backend has no driver mapping for.
class DatabaseCredential {
  final int databaseId;
  final String? type; // ORACLE | DAMENG | OCEANBASE | OTHER
  final String? host;
  final int? port;
  final String? serviceName;
  final String? username;
  final String? jdbcUrl;

  /// The decrypted password, or null when the backend has none stored.
  final String? secret;

  const DatabaseCredential({
    required this.databaseId,
    this.type,
    this.host,
    this.port,
    this.serviceName,
    this.username,
    this.jdbcUrl,
    this.secret,
  });

  factory DatabaseCredential.fromJson(Map<String, dynamic> json) {
    return DatabaseCredential(
      databaseId: (json['databaseId'] as num).toInt(),
      type: json['type'] as String?,
      host: json['host'] as String?,
      port: (json['port'] as num?)?.toInt(),
      serviceName: json['serviceName'] as String?,
      username: json['username'] as String?,
      jdbcUrl: json['jdbcUrl'] as String?,
      secret: json['secret'] as String?,
    );
  }
}
