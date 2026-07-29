import '../api/dto/component_dto.dart';
import '../api/dto/environment_dto.dart';
import 'environment_view.dart';

/// Anti-corruption layer for the Environment Catalog. Pure functions that
/// translate backend DTOs into the client's view models: enum strings become
/// localized labels, nulls become display placeholders, and the backend's wire
/// vocabulary is mapped to the product's ubiquitous language. Widgets depend on
/// the view models, never on the DTOs — so a change to the backend contract is
/// absorbed here and nowhere else.
class CatalogAcl {
  const CatalogAcl._();

  /// Placeholder for an Environment the backend returned without a name.
  static const String unnamedEnvironment = '未命名环境';

  /// Fixed data-freshness window: an Environment whose newest collection is
  /// older than this is flagged ⚠ stale. Deliberately a constant, not a setting.
  static const Duration staleAfter = Duration(hours: 24);

  /// [now] is injectable for tests; defaults to the wall clock.
  static EnvironmentView toView(EnvironmentDto dto, {DateTime? now}) {
    final name = (dto.name != null && dto.name!.trim().isNotEmpty)
        ? dto.name!.trim()
        : unnamedEnvironment;
    final components = dto.components.map(_componentToView).toList();
    return EnvironmentView(
      id: dto.id,
      name: name,
      memo: _blankToNull(dto.memo),
      components: components,
      health: _deriveHealth(components, now ?? DateTime.now()),
    );
  }

  static List<EnvironmentView> toViews(
    Iterable<EnvironmentDto> dtos, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    return dtos.map((dto) => toView(dto, now: at)).toList();
  }

  /// Decision 3: env health = worst-of component collection outcomes,
  /// excluding UNSUPPORTED components entirely (rollup and freshness alike).
  static EnvironmentHealth _deriveHealth(
    List<ComponentView> components,
    DateTime now,
  ) {
    var state = EnvironmentHealthState.ok;
    DateTime? newest;
    for (final c in components) {
      if (c.collectionState == CollectionState.unsupported) continue;
      if (c.collectionState == CollectionState.failed) {
        state = EnvironmentHealthState.failed;
      } else if (c.collectionState == CollectionState.notCollected &&
          state != EnvironmentHealthState.failed) {
        state = EnvironmentHealthState.pending;
      }
      final at = c.lastCollectedAt;
      if (at != null && (newest == null || at.isAfter(newest))) {
        newest = at;
      }
    }
    return EnvironmentHealth(
      state: state,
      newestCollectedAt: newest,
      isStale: newest != null && now.difference(newest) > staleAfter,
    );
  }

  /// Selectable Component role enums, in display order, for the edit form. Pair
  /// each with [roleLabel] for its localized label.
  static const List<String> roleCodes = [
    'UNSPECIFIED',
    'GATEWAY',
    'UI',
    'APP',
    'PRIVATE_PROTO',
  ];

  /// Selectable version-probe enums, in display order, for the edit form. Pair
  /// each with [versionProbeLabel] for its localized label.
  static const List<String> versionProbeCodes = [
    'DB',
    'SSH_FILE',
    'COMMAND',
    'HTTP',
    'NONE',
  ];

  static ComponentView _componentToView(ComponentDto dto) {
    return ComponentView(
      id: dto.id,
      roleCode: dto.role,
      roleLabel: roleLabel(dto.role),
      version: _blankToNull(dto.version),
      versionUpdatedAt: dto.versionUpdatedAt,
      logLocation: _blankToNull(dto.logLocation),
      listenPort: dto.listenPort,
      protocol: _blankToNull(dto.protocol),
      url: _blankToNull(dto.url),
      serverId: dto.serverId,
      databaseIds: List.unmodifiable(dto.databaseIds),
      versionProbeCode: dto.versionProbe,
      versionProbeLabel: versionProbeLabel(dto.versionProbe),
      collectionState: _collectionState(dto.collectionStatus),
      collectionStatusLabel: collectionStatusLabel(dto.collectionStatus),
      collectionDetail: _blankToNull(dto.collectionDetail),
      lastCollectedAt: dto.lastCollectedAt,
    );
  }

  /// Maps a backend Component role to its Chinese label. An unrecognized value
  /// is surfaced verbatim rather than dropped, so new server roles stay legible.
  static String roleLabel(String? role) {
    switch (role) {
      case 'GATEWAY':
        return '网关';
      case 'UI':
        return '界面';
      case 'APP':
        return '主服务';
      case 'PRIVATE_PROTO':
        return '专有协议服务';
      // An explicit "not yet classified" role (e.g. legacy-imported components), unified with the
      // null/blank case so there is a single term for "no role assigned".
      case 'UNSPECIFIED':
      case null:
      case '':
        return '未指定';
      default:
        return role;
    }
  }

  /// Assemble an Oracle Easy Connect login string for sqlplus / PL/SQL Developer:
  /// `username/password@host:port/serviceName`. The password segment is dropped
  /// when none is brokered (yielding `username@host…`, which prompts), and the
  /// credential prefix is dropped entirely when there's no username. Any missing
  /// coordinate is omitted; an empty string is returned when there is no host.
  static String sqlplusConnectString({
    String? username,
    String? password,
    String? host,
    int? port,
    String? serviceName,
  }) {
    final h = host?.trim();
    if (h == null || h.isEmpty) return '';
    final user = username?.trim() ?? '';
    final pass = password?.trim() ?? '';
    final credential = user.isEmpty
        ? ''
        : (pass.isEmpty ? user : '$user/$pass');
    final buf = StringBuffer();
    if (credential.isNotEmpty) buf.write('$credential@');
    buf.write(h);
    if (port != null) buf.write(':$port');
    final svc = serviceName?.trim();
    if (svc != null && svc.isNotEmpty) buf.write('/$svc');
    return buf.toString();
  }

  static String versionProbeLabel(String? probe) {
    switch (probe) {
      case 'DB':
        return '数据库查询';
      case 'SSH_FILE':
        return 'SSH 文件';
      case 'COMMAND':
        return '命令';
      case 'HTTP':
        return 'HTTP 接口';
      case 'NONE':
        return '无';
      case null:
      case '':
        return '未知';
      default:
        return probe;
    }
  }

  static String collectionStatusLabel(String? status) {
    switch (_collectionState(status)) {
      case CollectionState.ok:
        return '正常';
      case CollectionState.failed:
        return '失败';
      case CollectionState.unsupported:
        return '不支持';
      case CollectionState.notCollected:
        return '未采集';
    }
  }

  static CollectionState _collectionState(String? status) {
    switch (status) {
      case 'OK':
        return CollectionState.ok;
      case 'FAILED':
        return CollectionState.failed;
      case 'UNSUPPORTED':
        return CollectionState.unsupported;
      default:
        return CollectionState.notCollected;
    }
  }

  static String? _blankToNull(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
