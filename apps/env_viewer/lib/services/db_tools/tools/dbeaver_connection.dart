import '../db_tool.dart';

/// Builds DBeaver's `-con` connection spec: pipe-separated `key=value` pairs
/// (`dbeaver -con "driver=...|url=...|user=...|password=...|connect=true"`).
///
/// Prefers the brokered [DbConnectionTarget.jdbcUrl] when present (the backend
/// is authoritative on the connect string); otherwise falls back to discrete
/// host/port/database. [savePassword] defaults to false so the brokered secret
/// is used for this launch only and not written into DBeaver's stored
/// connection — the thin client persists nothing (ADR-0005).
String buildDbeaverConnectionSpec(
  DbConnectionTarget t, {
  bool savePassword = false,
}) {
  final parts = <String>['driver=${dbeaverDriverId(t.type)}'];

  final url = t.jdbcUrl;
  if (url != null && url.isNotEmpty) {
    parts.add('url=$url');
  } else {
    if (t.host != null && t.host!.isNotEmpty) parts.add('host=${t.host}');
    if (t.port != null) parts.add('port=${t.port}');
    if (t.database != null && t.database!.isNotEmpty) {
      parts.add('database=${t.database}');
    }
  }

  if (t.username != null && t.username!.isNotEmpty) {
    parts.add('user=${t.username}');
  }
  if (t.password != null && t.password!.isNotEmpty) {
    parts.add('password=${t.password}');
  }
  if (t.name != null && t.name!.isNotEmpty) parts.add('name=${t.name}');

  parts.add('save=${savePassword ? 'true' : 'false'}');
  parts.add('connect=true');
  return parts.join('|');
}

/// Maps a backend DatabaseType to a DBeaver driver id. Oracle has a first-class
/// built-in driver; the home-grown engines fall back to `generic`, paired with
/// the brokered `jdbcUrl` so DBeaver still has a complete connect string.
String dbeaverDriverId(String? type) => switch (type) {
  'ORACLE' => 'oracle',
  _ => 'generic',
};
