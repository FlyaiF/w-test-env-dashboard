/// Write payload for the non-secret coordinates of a shared Server.
class ServerInput {
  final String host;
  final String os;
  final SshAccessInput? ssh;

  const ServerInput({required this.host, required this.os, this.ssh});

  Map<String, dynamic> toJson() => {
    'host': host,
    'os': os,
    'ssh': ssh?.toJson(),
  };
}

/// Non-secret SSH connection metadata. Passwords remain brokered on demand.
class SshAccessInput {
  final String? host;
  final int? port;
  final String? username;

  const SshAccessInput({this.host, this.port, this.username});

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'username': username,
  };
}
