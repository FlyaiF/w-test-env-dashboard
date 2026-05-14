import '../ssh_tool.dart';

/// Builds a NetSarang `-url` value of the form
/// `<scheme>://user:password@host:port[/path]`. All credential components are
/// percent-encoded so passwords containing `@ : / ? # & space` survive a
/// round-trip through Xshell/Xftp's URL parser. When [includeStartPath] is
/// true and [t.startPath] is set, the remote path is appended with each
/// segment percent-encoded.
String buildNetsarangUrl(
  String scheme,
  ConnectionTarget t, {
  bool includeStartPath = false,
}) {
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
  if (includeStartPath &&
      t.startPath != null &&
      t.startPath!.trim().isNotEmpty) {
    final segments = t.startPath!
        .split('/')
        .where((s) => s.isNotEmpty)
        .map(Uri.encodeComponent);
    buf.write('/');
    buf.write(segments.join('/'));
  }
  return buf.toString();
}
