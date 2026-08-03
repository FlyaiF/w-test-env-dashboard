import '../api/dto/database_dto.dart';
import '../api/dto/server_dto.dart';
import 'inventory_view.dart';

/// Translates Resource Inventory wire DTOs into localized presentation models.
class InventoryAcl {
  const InventoryAcl._();

  static ServerView toServerView(ServerDto dto) => ServerView(
    id: dto.id,
    host: _blankToNull(dto.host),
    os: _blankToNull(dto.os),
    osLabel: serverOsLabel(dto.os),
    sshHost: _blankToNull(dto.ssh?.host),
    sshPort: dto.ssh?.port,
    sshUsername: _blankToNull(dto.ssh?.username),
    hasSecret: dto.hasSecret,
    referenceCount: dto.referenceCount,
  );

  static List<ServerView> toServerViews(Iterable<ServerDto> dtos) {
    final views = dtos.map(toServerView).toList()
      ..sort(
        (left, right) => _byDisplayLabelThenId(
          left.displayLabel,
          left.id,
          right.displayLabel,
          right.id,
        ),
      );
    return List.unmodifiable(views);
  }

  static String serverOsLabel(String? os) {
    switch (os?.trim()) {
      case 'LINUX':
        return 'Linux';
      case 'WINDOWS':
        return 'Windows';
      case null:
      case '':
        return '未指定';
      default:
        return os!.trim();
    }
  }

  static DatabaseView toDatabaseView(DatabaseDto dto) {
    final connection = dto.connection;
    return DatabaseView(
      id: dto.id,
      role: _blankToNull(dto.role),
      roleLabel: databaseRoleLabel(dto.role),
      type: _blankToNull(dto.type),
      typeLabel: databaseTypeLabel(dto.type),
      host: _blankToNull(connection?.host),
      port: connection?.port,
      serviceName: _blankToNull(connection?.serviceName),
      username: _blankToNull(connection?.username),
      hasSecret: dto.hasSecret,
      referenceCount: dto.referenceCount,
    );
  }

  static List<DatabaseView> toDatabaseViews(Iterable<DatabaseDto> dtos) {
    final views = dtos.map(toDatabaseView).toList()
      ..sort(
        (left, right) => _byDisplayLabelThenId(
          left.displayLabel,
          left.id,
          right.displayLabel,
          right.id,
        ),
      );
    return List.unmodifiable(views);
  }

  static String databaseRoleLabel(String? role) {
    switch (role?.trim()) {
      case 'business':
        return '业务库';
      case 'intermediate':
        return '中转库';
      case null:
      case '':
        return '未指定';
      default:
        return role!.trim();
    }
  }

  static String databaseTypeLabel(String? type) {
    switch (type?.trim()) {
      case 'ORACLE':
        return 'Oracle';
      case 'DAMENG':
        return '达梦';
      case 'OCEANBASE':
        return 'OceanBase';
      case 'OTHER':
        return '其他';
      case null:
      case '':
        return '未指定';
      default:
        return type!.trim();
    }
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static int _byDisplayLabelThenId(
    String leftLabel,
    int leftId,
    String rightLabel,
    int rightId,
  ) {
    final labelOrder = leftLabel.toLowerCase().compareTo(
      rightLabel.toLowerCase(),
    );
    return labelOrder != 0 ? labelOrder : leftId.compareTo(rightId);
  }
}
