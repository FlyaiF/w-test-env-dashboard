/// Write payload for a shared, role-specific Database access profile.
class DatabaseInput {
  final String? role;
  final String type;
  final DatabaseConnectionInput? connection;

  const DatabaseInput({this.role, required this.type, this.connection});

  Map<String, dynamic> toJson() => {
    'role': role,
    'type': type,
    'connection': connection?.toJson(),
  };
}

/// Non-secret database connection metadata. Passwords remain brokered on demand.
class DatabaseConnectionInput {
  final String? host;
  final int? port;
  final String? serviceName;
  final String? username;

  const DatabaseConnectionInput({
    this.host,
    this.port,
    this.serviceName,
    this.username,
  });

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'serviceName': serviceName,
    'username': username,
  };
}
