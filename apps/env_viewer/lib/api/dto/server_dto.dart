/// Wire shape of a shared `Server` aggregate as published by the backend Resource
/// Inventory (`ServerDto`), fetched from `GET /api/servers`. A faithful mirror of
/// the server contract; the anti-corruption layer resolves it into a display label.
/// Only the fields the client needs to render a reference are kept — the nested
/// `ssh` access block is intentionally ignored (it is never shown).
class ServerDto {
  final int id;
  final String? host;
  final String? os; // LINUX | WINDOWS

  const ServerDto({required this.id, this.host, this.os});

  factory ServerDto.fromJson(Map<String, dynamic> json) {
    return ServerDto(
      id: (json['id'] as num).toInt(),
      host: json['host'] as String?,
      os: json['os'] as String?,
    );
  }
}
