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

  static EnvironmentView toView(EnvironmentDto dto) {
    final name = (dto.name != null && dto.name!.trim().isNotEmpty)
        ? dto.name!.trim()
        : unnamedEnvironment;
    return EnvironmentView(
      id: dto.id,
      name: name,
      memo: _blankToNull(dto.memo),
      components: dto.components.map(_componentToView).toList(),
    );
  }

  static List<EnvironmentView> toViews(Iterable<EnvironmentDto> dtos) =>
      dtos.map(toView).toList();

  static ComponentView _componentToView(ComponentDto dto) {
    return ComponentView(
      id: dto.id,
      roleLabel: roleLabel(dto.role),
      version: _blankToNull(dto.version),
      deployTime: dto.deployTime,
      logLocation: _blankToNull(dto.logLocation),
      listenPort: dto.listenPort,
      protocol: _blankToNull(dto.protocol),
      url: _blankToNull(dto.url),
      serverId: dto.serverId,
      databaseIds: List.unmodifiable(dto.databaseIds),
      versionProbeLabel: versionProbeLabel(dto.versionProbe),
      collectionState: _collectionState(dto.collectionStatus),
      collectionStatusLabel: collectionStatusLabel(dto.collectionStatus),
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
      case null:
      case '':
        return '未知组件';
      default:
        return role;
    }
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
