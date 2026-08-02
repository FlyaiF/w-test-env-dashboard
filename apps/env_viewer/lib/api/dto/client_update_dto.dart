/// Mirror of the backend `ClientUpdateDto`: the newest published env_viewer
/// build for this platform, with the SHA-256 the client must verify before
/// handing the download to the updater helper.
class ClientUpdateDto {
  final String version;
  final String platform;
  final String fileName;
  final int sizeBytes;
  final String sha256;
  final String? notes;

  const ClientUpdateDto({
    required this.version,
    required this.platform,
    required this.fileName,
    required this.sizeBytes,
    required this.sha256,
    this.notes,
  });

  factory ClientUpdateDto.fromJson(Map<String, dynamic> json) {
    return ClientUpdateDto(
      version: json['version'] as String,
      platform: json['platform'] as String,
      fileName: json['fileName'] as String,
      sizeBytes: (json['sizeBytes'] as num).toInt(),
      sha256: json['sha256'] as String,
      notes: json['notes'] as String?,
    );
  }
}
