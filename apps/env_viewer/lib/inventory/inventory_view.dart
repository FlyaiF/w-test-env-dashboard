/// Presentation models for the shared Resource Inventory. These models expose
/// only non-secret Server and Database metadata; credentials remain brokered
/// on demand and never enter inventory state.
library;

class ServerView {
  final int id;
  final String? host;

  /// Raw backend enum, retained so edit forms can round-trip it.
  final String? os;
  final String osLabel;
  final String? sshHost;
  final int? sshPort;
  final String? sshUsername;

  const ServerView({
    required this.id,
    this.host,
    this.os,
    this.osLabel = '未指定',
    this.sshHost,
    this.sshPort,
    this.sshUsername,
  });

  String get displayLabel => host ?? '#$id';

  String get sshAddress {
    final addressHost = sshHost ?? host;
    if (addressHost == null) return '';
    final buffer = StringBuffer();
    if (sshUsername != null) buffer.write('$sshUsername@');
    buffer.write(addressHost);
    if (sshPort != null && sshPort != 22) buffer.write(':$sshPort');
    return buffer.toString();
  }
}

class DatabaseView {
  final int id;

  /// Raw role/type values, retained for editing and round-tripping.
  final String? role;
  final String roleLabel;
  final String? type;
  final String typeLabel;
  final String? host;
  final int? port;
  final String? serviceName;
  final String? username;

  const DatabaseView({
    required this.id,
    this.role,
    required this.roleLabel,
    this.type,
    required this.typeLabel,
    this.host,
    this.port,
    this.serviceName,
    this.username,
  });

  String get address {
    final addressHost = host;
    if (addressHost == null) return '';
    final buffer = StringBuffer(addressHost);
    if (port != null) buffer.write(':$port');
    if (serviceName != null) buffer.write('/$serviceName');
    return buffer.toString();
  }

  String get displayLabel {
    final parts = [
      roleLabel,
      typeLabel,
      address,
    ].where((part) => part.isNotEmpty).toList(growable: false);
    return parts.isEmpty ? '#$id' : parts.join(' · ');
  }

  /// Compact label used in database-tool menus.
  String get menuLabel {
    final label = host == null ? roleLabel : '$roleLabel $host';
    return label.trim().isEmpty ? '#$id' : label.trim();
  }
}
