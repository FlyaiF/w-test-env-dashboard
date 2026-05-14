/// Parse E_WEBSERVERADDR format: "server_addr&username/password"
/// Returns (host, port, username, password)
({String host, int port, String? username, String? password}) parseServerAddr(
  String addr,
) {
  String serverPart = addr;
  String? username;
  String? password;

  // Split by '&' to get server and credentials
  final ampIdx = addr.indexOf('&');
  if (ampIdx != -1) {
    serverPart = addr.substring(0, ampIdx);
    final credPart = addr.substring(ampIdx + 1);
    final slashIdx = credPart.indexOf('/');
    if (slashIdx != -1) {
      username = credPart.substring(0, slashIdx);
      password = credPart.substring(slashIdx + 1);
    } else {
      username = credPart;
    }
  }

  // Parse host:port
  final parts = serverPart.split(':');
  final host = parts[0];
  final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 22 : 22;

  return (host: host, port: port, username: username, password: password);
}
