import '../../api/dto/database_credential.dart';
import '../../api/dto/server_credential.dart';
import '../db_tools/db_tool.dart';
import '../ssh_tools/ssh_tool.dart';

/// Adapts brokered credential bundles (ADR-0005) into the launch targets the
/// SSH and DB tools consume. Pure mapping — the secret rides straight from the
/// on-demand response into the target and is never written to disk.

/// SSH target from a brokered [ServerCredential]. Falls back to port 22 when the
/// Server has no recorded SSH port.
ConnectionTarget sshTargetFromServer(
  ServerCredential credential, {
  String? startPath,
}) {
  return ConnectionTarget(
    host: credential.host ?? '',
    port: credential.port ?? 22,
    username: credential.username,
    password: credential.secret,
    startPath: startPath,
  );
}

/// DB target from a brokered [DatabaseCredential].
DbConnectionTarget dbTargetFromDatabase(
  DatabaseCredential credential, {
  String? name,
}) {
  return DbConnectionTarget(
    type: credential.type,
    host: credential.host,
    port: credential.port,
    database: credential.serviceName,
    username: credential.username,
    password: credential.secret,
    jdbcUrl: credential.jdbcUrl,
    name: name,
  );
}
