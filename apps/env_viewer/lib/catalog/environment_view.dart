/// UI-facing view models for the Environment Catalog. These speak the product's
/// ubiquitous language (Environment, Component, Version, …) and carry only what
/// the presentation layer needs — already-localized labels and display-ready
/// values. They are produced by [CatalogAcl] from the backend DTOs so backend
/// wire shapes never leak into widgets.
library;

/// Collection outcome for a Component, decoupled from the backend's enum string
/// so the UI can colour/branch on it without matching raw values.
enum CollectionState { ok, failed, unsupported, notCollected }

/// Environment-level health rollup: worst-of the collectable Components'
/// collection outcomes. UNSUPPORTED Components are excluded — they render a
/// neutral chip and never drag an Environment's health down.
enum EnvironmentHealthState {
  /// ● 正常 — every collectable Component collected OK (or nothing to collect).
  ok,

  /// ○ 待采集 — nothing failed, but at least one Component awaits collection.
  pending,

  /// ✗ 异常 — at least one Component's collection FAILED.
  failed,
}

/// Derived, client-side health for one Environment (no API involved): the
/// rollup state plus data freshness. [isStale] flags an Environment whose
/// newest collection across collectable Components is older than the fixed
/// 24h window; a never-collected Environment is not stale (待采集 covers it).
class EnvironmentHealth {
  final EnvironmentHealthState state;

  /// Newest `lastCollectedAt` across collectable Components; null when none
  /// has ever been collected.
  final DateTime? newestCollectedAt;
  final bool isStale;

  const EnvironmentHealth({
    required this.state,
    this.newestCollectedAt,
    this.isStale = false,
  });
}

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

  /// Why the last collection went non-OK (probe detail), or null.
  final String? collectionDetail;
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
    this.collectionDetail,
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

  /// Client-derived health rollup + staleness for the roster row.
  final EnvironmentHealth health;

  const EnvironmentView({
    required this.id,
    required this.name,
    this.memo,
    this.components = const [],
    this.health = const EnvironmentHealth(state: EnvironmentHealthState.ok),
  });

  int get componentCount => components.length;
}
