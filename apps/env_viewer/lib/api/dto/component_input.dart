/// Write-direction payload for a Component — the mirror of [ComponentDto] used to drive
/// `POST`/`PUT` against the backend's nested Component endpoints. Field names and enum strings
/// match the server's `ComponentRequest` contract verbatim. It deliberately carries only the
/// curated descriptive fields: links (runs-on / uses) and collected status are owned by other
/// endpoints, so editing a Component here never touches them.
class ComponentInput {
  /// Wire enum: UNSPECIFIED | GATEWAY | UI | APP | PRIVATE_PROTO. Required by the backend.
  final String role;
  final String? version;
  final DateTime? versionUpdatedAt;
  final String? logLocation;
  final int? listenPort;
  final String? protocol;
  final String? url;

  /// Wire enum: DB | SSH_FILE | COMMAND | HTTP | NONE, or null.
  final String? versionProbe;

  const ComponentInput({
    required this.role,
    this.version,
    this.versionUpdatedAt,
    this.logLocation,
    this.listenPort,
    this.protocol,
    this.url,
    this.versionProbe,
  });

  Map<String, dynamic> toJson() => {
    'role': role,
    'version': version,
    // Instants cross the wire as UTC ISO-8601, matching the read DTO's parsing.
    'versionUpdatedAt': versionUpdatedAt?.toUtc().toIso8601String(),
    'logLocation': logLocation,
    'listenPort': listenPort,
    'protocol': protocol,
    'url': url,
    'versionProbe': versionProbe,
  };
}
