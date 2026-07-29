/// Wire shape of a Component as published by the backend Environment Catalog
/// (`ComponentDto`). This is a faithful mirror of the server contract — field
/// names and enum strings are taken verbatim. The anti-corruption layer
/// (`CatalogAcl`) translates it into a UI-facing view model; UI code never
/// touches this type directly.
class ComponentDto {
  final int id;
  final String? role; // UNSPECIFIED | GATEWAY | UI | APP | PRIVATE_PROTO
  final String? version;
  final DateTime? versionUpdatedAt;
  final String? logLocation;
  final int? listenPort;
  final String? protocol;
  final String? url;
  final int? serverId;
  final List<int> databaseIds;
  final String? versionProbe; // DB | SSH_FILE | COMMAND | HTTP | NONE
  final String? collectionStatus; // OK | FAILED | UNSUPPORTED

  /// Why the last collection went non-OK; null after a successful collection.
  final String? collectionDetail;
  final DateTime? lastCollectedAt;

  const ComponentDto({
    required this.id,
    this.role,
    this.version,
    this.versionUpdatedAt,
    this.logLocation,
    this.listenPort,
    this.protocol,
    this.url,
    this.serverId,
    this.databaseIds = const [],
    this.versionProbe,
    this.collectionStatus,
    this.collectionDetail,
    this.lastCollectedAt,
  });

  factory ComponentDto.fromJson(Map<String, dynamic> json) {
    return ComponentDto(
      id: (json['id'] as num).toInt(),
      role: json['role'] as String?,
      version: json['version'] as String?,
      versionUpdatedAt: _parseInstant(json['versionUpdatedAt']),
      logLocation: json['logLocation'] as String?,
      listenPort: (json['listenPort'] as num?)?.toInt(),
      protocol: json['protocol'] as String?,
      url: json['url'] as String?,
      serverId: (json['serverId'] as num?)?.toInt(),
      databaseIds:
          (json['databaseIds'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [],
      versionProbe: json['versionProbe'] as String?,
      collectionStatus: json['collectionStatus'] as String?,
      collectionDetail: json['collectionDetail'] as String?,
      lastCollectedAt: _parseInstant(json['lastCollectedAt']),
    );
  }

  static DateTime? _parseInstant(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
