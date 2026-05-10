import 'ssh_tool.dart';
import 'tools/macos_terminal_tool.dart';
import 'tools/xftp_tool.dart';
import 'tools/xshell_tool.dart';

/// Registry of built-in SSH/SFTP tools. Adding a new tool is one entry here
/// plus a class that implements [SshTool]; the dashboard launcher and the
/// settings page pick it up automatically via [availableFor] / [all].
class SshToolRegistry {
  static final List<SshTool> _all = [
    XshellTool(),
    XftpTool(),
    MacosTerminalTool(),
  ];

  static List<SshTool> get all => List.unmodifiable(_all);

  static List<SshTool> get availableOnPlatform =>
      _all.where((t) => t.isAvailableOnPlatform).toList(growable: false);

  static List<SshTool> availableFor(SshToolKind kind) => _all
      .where((t) => t.isAvailableOnPlatform && t.kind == kind)
      .toList(growable: false);

  static SshTool? byId(String? id) {
    if (id == null) return null;
    for (final t in _all) {
      if (t.id == id) return t;
    }
    return null;
  }
}
