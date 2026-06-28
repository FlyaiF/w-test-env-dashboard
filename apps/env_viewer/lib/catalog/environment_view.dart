/// UI-facing view models for the Environment Catalog. These speak the product's
/// ubiquitous language (Environment, Component, Version, …) and carry only what
/// the presentation layer needs — already-localized labels and display-ready
/// values. They are produced by [CatalogAcl] from the backend DTOs so backend
/// wire shapes never leak into widgets.

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
  final DateTime? deployTime;
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
    this.deployTime,
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

/// A resolved Server reference, ready to render. Built by [CatalogAcl] from a
/// `ServerDto` so a Component's `serverId` shows a host instead of a bare `#id`.
class ServerRefView {
  final int id;
  final String? host;

  const ServerRefView({required this.id, this.host});

  /// Label for the component card's 运行主机 field — the host, or `#id` if blank.
  String get cardLabel => (host != null && host!.trim().isNotEmpty)
      ? host!.trim()
      : '#$id';
}

/// A resolved Database reference, ready to render. Built by [CatalogAcl] from a
/// `DatabaseDto`. Carries two label forms: a full one for the card and a short
/// one (role + host) to disambiguate a multi-database launch menu.
class DatabaseRefView {
  final int id;

  /// Localized role label (e.g. 业务库), or the raw role for an unknown value.
  final String roleLabel;

  /// Localized engine label (e.g. Oracle), or the raw type for an unknown value.
  final String typeLabel;
  final String? host;
  final int? port;
  final String? serviceName;

  const DatabaseRefView({
    required this.id,
    required this.roleLabel,
    required this.typeLabel,
    this.host,
    this.port,
    this.serviceName,
  });

  /// `host[:port][/serviceName]`, with any missing part omitted; empty if no host.
  String get address {
    final h = host?.trim();
    if (h == null || h.isEmpty) return '';
    final buf = StringBuffer(h);
    if (port != null) buf.write(':$port');
    final svc = serviceName?.trim();
    if (svc != null && svc.isNotEmpty) buf.write('/$svc');
    return buf.toString();
  }

  /// Full label for the card's 使用数据库 field: `role · type · address`,
  /// dropping any blank segment.
  String get cardLabel {
    final parts = [roleLabel, typeLabel, address]
        .where((p) => p.trim().isNotEmpty)
        .toList();
    return parts.isEmpty ? '#$id' : parts.join(' · ');
  }

  /// Short label for the launch menu: `role host` (host only), trimmed.
  String get menuLabel {
    final h = host?.trim();
    final label = (h != null && h.isNotEmpty)
        ? '$roleLabel $h'.trim()
        : roleLabel.trim();
    return label.isEmpty ? '#$id' : label;
  }
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
