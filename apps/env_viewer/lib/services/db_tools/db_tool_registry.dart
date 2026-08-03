import 'db_tool.dart';
import 'tools/dbeaver_tool.dart';
import 'tools/plsqldev_tool.dart';

/// Registry of built-in DB tools, mirroring `SshToolRegistry`. Adding a tool is
/// one entry here plus a class implementing [DbTool]; the launcher and settings
/// page pick it up via [all] / [availableOnPlatform].
class DbToolRegistry {
  static final List<DbTool> _all = [
    DbeaverTool(),
    PlsqldevTool(),
  ];

  static List<DbTool> get all => List.unmodifiable(_all);

  static List<DbTool> get availableOnPlatform =>
      _all.where((t) => t.isAvailableOnPlatform).toList(growable: false);

  static DbTool? byId(String? id) {
    if (id == null) return null;
    for (final t in _all) {
      if (t.id == id) return t;
    }
    return null;
  }
}
