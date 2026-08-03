import 'component_input.dart';

/// Write-direction payload for an Environment — the mirror of `EnvironmentDto` used to drive
/// `POST`/`PUT /api/environments`. Matches the server's `EnvironmentRequest`: [components] seed the
/// aggregate on create and are ignored on update (Components are then curated through their own
/// nested endpoints).
class EnvironmentInput {
  final String name;
  final String? memo;

  /// Link to this environment's console in SEE (公司环境管理平台).
  final String? seeUrl;
  final List<ComponentInput> components;

  const EnvironmentInput({
    required this.name,
    this.memo,
    this.seeUrl,
    this.components = const [],
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'memo': memo,
    'seeUrl': seeUrl,
    // Only sent when seeding on create; the backend ignores components on update,
    // so an empty list is omitted rather than put on the wire misleadingly.
    if (components.isNotEmpty)
      'components': components.map((c) => c.toJson()).toList(),
  };
}
