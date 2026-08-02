import '../db_tool.dart';

/// Builds PL/SQL Developer's `userid=` logon argument:
/// `user/password@host:port/service` (EZConnect, resolved by the local Oracle
/// client). Returns null when the target lacks the coordinates to form one.
///
/// The password segment is omitted when no secret was brokered — PL/SQL
/// Developer then prompts for it instead of failing the logon.
String? buildPlsqldevUserid(DbConnectionTarget t) {
  final host = t.host;
  if (host == null || host.isEmpty) return null;
  final username = t.username;
  if (username == null || username.isEmpty) return null;

  final buffer = StringBuffer(username);
  final password = t.password;
  if (password != null && password.isNotEmpty) {
    buffer.write('/$password');
  }
  buffer.write('@$host');
  if (t.port != null) buffer.write(':${t.port}');
  final service = t.database;
  if (service != null && service.isNotEmpty) buffer.write('/$service');
  return buffer.toString();
}
