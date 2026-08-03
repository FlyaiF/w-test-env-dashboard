/// Wire shape of a brokered SSH credential bundle for a Server
/// (`ServerCredentialDto`). Fetched on demand from the backend's Access
/// Brokering endpoint just before launching the user's own SSH tool, and
/// discarded after — the thin client persists no secrets (ADR-0005).
class ServerCredential {
  final int serverId;
  final String? host;
  final int? port;
  final String? username;

  /// The decrypted secret (password / key passphrase), or null when the
  /// backend has none stored for this Server.
  final String? secret;

  const ServerCredential({
    required this.serverId,
    this.host,
    this.port,
    this.username,
    this.secret,
  });

  factory ServerCredential.fromJson(Map<String, dynamic> json) {
    return ServerCredential(
      serverId: (json['serverId'] as num).toInt(),
      host: json['host'] as String?,
      port: (json['port'] as num?)?.toInt(),
      username: json['username'] as String?,
      secret: json['secret'] as String?,
    );
  }
}
