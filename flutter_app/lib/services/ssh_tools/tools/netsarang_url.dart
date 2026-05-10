import '../ssh_tool.dart';

/// Builds a NetSarang `-url` value of the form `<scheme>://user:password@host:port`.
/// All credential components are percent-encoded so passwords containing
/// `@ : / ? # & space` survive a round-trip through Xshell/Xftp's URL parser.
String buildNetsarangUrl(String scheme, ConnectionTarget t) {
  final buf = StringBuffer('$scheme://');
  final user = t.username;
  final pwd = t.password;
  if (user != null && user.isNotEmpty) {
    buf.write(Uri.encodeComponent(user));
    if (pwd != null && pwd.isNotEmpty) {
      buf.write(':');
      buf.write(Uri.encodeComponent(pwd));
    }
    buf.write('@');
  }
  buf.write(t.host);
  buf.write(':');
  buf.write(t.port);
  return buf.toString();
}
