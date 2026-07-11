/// UI-facing view models for the Environment Catalog. These speak the product's
/// ubiquitous language (Environment, Component, Version, …) and carry only what
/// the presentation layer needs — already-localized labels and display-ready
/// values. They are produced by [CatalogAcl] from the backend DTOs so backend
/// wire shapes never leak into widgets.
library;

/// Collection outcome for a Component, decoupled from the backend's enum string
/// so the UI can colour/branch on it without matching raw values.
enum CollectionState { ok, failed, unsupported, notCollected }

/// One deployable part of an Environment, ready to render.
class ComponentView {
  final int id;

  /// Raw backend role enum (e.g. GATEWAY), or null. Kept alongside the label so
  /// the edit form can preselect it and round-trip without reverse-mapping.
  final String? roleCode;

  /// Localized role label (e.g. 网关). Falls back to the raw value for an
  /// unrecognized role rather than hiding it.
  final String roleLabel;

  /// Live version string, or null when blank/unknown.
  final String? version;
  final DateTime? versionUpdatedAt;
  final String? logLocation;
  final int? listenPort;
  final String? protocol;

  /// Reachability URL, if the Component publishes one.
  final String? url;

  /// Reference (by ID) into the Resource Inventory — the Server this Component
  /// runs on. Not resolved to a Server in this slice.
  final int? serverId;

  /// References (by ID) into the Resource Inventory — Databases this Component
  /// uses. Not resolved in this slice.
  final List<int> databaseIds;

  /// Raw backend version-probe enum (e.g. HTTP), or null. Kept for the edit form.
  final String? versionProbeCode;

  /// Localized version-probe label (e.g. HTTP接口).
  final String versionProbeLabel;

  final CollectionState collectionState;

  /// Localized collection-status label (e.g. 正常 / 未采集).
  final String collectionStatusLabel;
  final DateTime? lastCollectedAt;

  const ComponentView({
    required this.id,
    this.roleCode,
    required this.roleLabel,
    this.version,
    this.versionUpdatedAt,
    this.logLocation,
    this.listenPort,
    this.protocol,
    this.url,
    this.serverId,
    this.databaseIds = const [],
    this.versionProbeCode,
    required this.versionProbeLabel,
    required this.collectionState,
    required this.collectionStatusLabel,
    this.lastCollectedAt,
  });
}

/// One test deployment — the aggregate root, with its owned Components.
class EnvironmentView {
  final int id;

  /// Display name, never null (falls back to a placeholder for an unnamed row).
  final String name;
  final String? memo;
  final List<ComponentView> components;

  const EnvironmentView({
    required this.id,
    required this.name,
    this.memo,
    this.components = const [],
  });

  int get componentCount => components.length;
}
