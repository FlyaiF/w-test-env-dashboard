import 'package:flutter/foundation.dart';

import '../services/ssh_tools/ssh_tool.dart' show PasswordMode;
import 'config_service.dart';

/// Presentation-side holder for the thin client's persisted [AppConfig]
/// (Local Desktop Integration). Loaded once at startup, exposes typed getters for
/// the launch path and the Settings page, and persists every edit through
/// [ConfigService]. Holds no durable secrets (ADR-0005).
class ConfigStore extends ChangeNotifier {
  final AppConfig _config;

  /// The `ENV_DASHBOARD_BACKEND_URL` value captured at startup, or null. When
  /// present it wins over the saved URL and locks the Settings field, so the
  /// override is never silent.
  final String? backendUrlEnvOverride;

  ConfigStore(this._config, {this.backendUrlEnvOverride});

  /// Load config from disk and wrap it. [backendUrlEnvOverride] is the captured
  /// env-var value (or null) so Settings can lock/annotate the URL field.
  static Future<ConfigStore> load({String? backendUrlEnvOverride}) async {
    final cfg = await ConfigService.load();
    return ConfigStore(cfg, backendUrlEnvOverride: backendUrlEnvOverride);
  }

  AppConfig get config => _config;

  // --- Backend URL ---------------------------------------------------------

  /// True when an env var is forcing the backend URL — the field is read-only.
  bool get backendUrlLocked =>
      backendUrlEnvOverride != null && backendUrlEnvOverride!.isNotEmpty;

  /// The URL to display in the field: the env override if locked, else the saved
  /// value (empty string when neither is set).
  String get effectiveBackendUrl => backendUrlLocked
      ? backendUrlEnvOverride!
      : (_config.backendBaseUrl ?? '');

  // --- Tool launch preferences --------------------------------------------

  PasswordMode get passwordMode => _config.sshTools.passwordMode == 'clipboard'
      ? PasswordMode.clipboard
      : PasswordMode.argv;

  String? get defaultTerminalToolId => _config.sshTools.defaultTerminalToolId;
  String? get defaultSftpToolId => _config.sshTools.defaultSftpToolId;
  String? get defaultDbToolId => _config.dbTools.defaultToolId;

  /// Non-empty SSH tool executable overrides, keyed by tool id.
  Map<String, String> get sshExecutablePaths =>
      Map.unmodifiable(_config.sshTools.executablePaths);

  /// Non-empty DB tool executable overrides, keyed by tool id.
  Map<String, String> get dbExecutablePaths =>
      Map.unmodifiable(_config.dbTools.executablePaths);

  /// The configured executable override for a tool id (either section; ids are
  /// unique across registries), or null when none is set.
  String? executablePathFor(String toolId) {
    final ssh = _config.sshTools.executablePaths[toolId];
    if (ssh != null && ssh.trim().isNotEmpty) return ssh.trim();
    final db = _config.dbTools.executablePaths[toolId];
    if (db != null && db.trim().isNotEmpty) return db.trim();
    return null;
  }

  // --- Mutations (persist + notify) ---------------------------------------

  Future<void> setBackendBaseUrl(String? url) {
    final trimmed = url?.trim();
    _config.backendBaseUrl = (trimmed == null || trimmed.isEmpty)
        ? null
        : trimmed;
    return _save();
  }

  Future<void> setSshExecutablePath(String toolId, String path) {
    _put(_config.sshTools.executablePaths, toolId, path);
    return _save();
  }

  Future<void> setDbExecutablePath(String toolId, String path) {
    _put(_config.dbTools.executablePaths, toolId, path);
    return _save();
  }

  Future<void> setDefaultTerminalToolId(String? id) {
    _config.sshTools.defaultTerminalToolId = _norm(id);
    return _save();
  }

  Future<void> setDefaultSftpToolId(String? id) {
    _config.sshTools.defaultSftpToolId = _norm(id);
    return _save();
  }

  Future<void> setDefaultDbToolId(String? id) {
    _config.dbTools.defaultToolId = _norm(id);
    return _save();
  }

  Future<void> setPasswordMode(PasswordMode mode) {
    _config.sshTools.passwordMode = mode == PasswordMode.clipboard
        ? 'clipboard'
        : 'argv';
    return _save();
  }

  void _put(Map<String, String> map, String key, String value) {
    final v = value.trim();
    if (v.isEmpty) {
      map.remove(key);
    } else {
      map[key] = v;
    }
  }

  String? _norm(String? id) =>
      (id == null || id.trim().isEmpty) ? null : id.trim();

  Future<void> _save() async {
    await ConfigService.save(_config);
    notifyListeners();
  }
}
