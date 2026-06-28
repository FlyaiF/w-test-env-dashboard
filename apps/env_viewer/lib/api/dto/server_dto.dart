/// Wire shape of a shared `Server` aggregate as published by the backend Resource
/// Inventory (`ServerDto`), fetched from `GET /api/servers`. A faithful mirror of
/// the server contract; the anti-corruption layer resolves it into a display label.
/// The nested [ssh] block carries only non-secret coordinates (host/port/username —
/// no password, which is brokered) and backs the card's SSH 信息 section.
class ServerDto {
  final int id;
  final String? host;
  final String? os; // LINUX | WINDOWS
  final SshAccessInfo? ssh;

  const ServerDto({required this.id, this.host, this.os, this.ssh});

  factory ServerDto.fromJson(Map<String, dynamic> json) {
    final ssh = json['ssh'];
    return ServerDto(
      id: (json['id'] as num).toInt(),
      host: json['host'] as String?,
      os: json['os'] as String?,
      ssh: ssh is Map<String, dynamic> ? SshAccessInfo.fromJson(ssh) : null,
    );
  }
}

/// Non-secret SSH access coordinates on the wire (`SshAccessDto`): no password or
/// key — those are delivered only by the Access Broker on demand.
class SshAccessInfo {
  final String? host;
  final int? port;
  final String? username;

  const SshAccessInfo({this.host, this.port, this.username});

  factory SshAccessInfo.fromJson(Map<String, dynamic> json) {
    return SshAccessInfo(
      host: json['host'] as String?,
      port: (json['port'] as num?)?.toInt(),
      username: json['username'] as String?,
    );
  }
}
