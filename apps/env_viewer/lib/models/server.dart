class Server {
  final String host;
  final int port;
  final String? label;
  final String? sshUsername;
  final String? sshPassword;
  final bool isLocalOnly;

  Server({
    required this.host,
    this.port = 22,
    this.label,
    this.sshUsername,
    this.sshPassword,
    this.isLocalOnly = false,
  });

  factory Server.fromJson(Map<String, dynamic> json) {
    return Server(
      host: json['host'] as String,
      port: json['port'] as int? ?? 22,
      label: json['label'] as String?,
      sshUsername: json['sshUsername'] as String?,
      sshPassword: json['sshPassword'] as String?,
      isLocalOnly: json['isLocalOnly'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'host': host,
      'port': port,
      if (label != null) 'label': label,
      if (sshUsername != null) 'sshUsername': sshUsername,
      if (sshPassword != null) 'sshPassword': sshPassword,
      'isLocalOnly': isLocalOnly,
    };
  }

  Server copyWith({
    String? host,
    int? port,
    String? label,
    String? sshUsername,
    String? sshPassword,
    bool? isLocalOnly,
  }) {
    return Server(
      host: host ?? this.host,
      port: port ?? this.port,
      label: label ?? this.label,
      sshUsername: sshUsername ?? this.sshUsername,
      sshPassword: sshPassword ?? this.sshPassword,
      isLocalOnly: isLocalOnly ?? this.isLocalOnly,
    );
  }
}
