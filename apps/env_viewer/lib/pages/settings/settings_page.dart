import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../config/config_store.dart';
import '../../services/db_tools/db_tool.dart';
import '../../services/db_tools/db_tool_registry.dart';
import '../../services/ssh_tools/ssh_tool.dart';
import '../../services/ssh_tools/ssh_tool_registry.dart';

/// Local Desktop Integration settings: appearance, where the user's own SSH/DB
/// tools live, which tool is the default, how passwords are handed to a
/// terminal, and the backend address. Persists through [ConfigStore]; stores
/// no secrets (ADR-0005). Every persisted change confirms with an inline 已保存.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _backendUrl;
  // One path controller per tool id (SSH + DB tools share the id space).
  final Map<String, TextEditingController> _paths = {};
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final store = context.read<ConfigStore>();
    _backendUrl = TextEditingController(text: store.effectiveBackendUrl);
    for (final t in SshToolRegistry.all) {
      _paths[t.id] = TextEditingController(
        text: store.config.sshTools.executablePaths[t.id] ?? '',
      );
    }
    for (final t in DbToolRegistry.all) {
      _paths[t.id] = TextEditingController(
        text: store.config.dbTools.executablePaths[t.id] ?? '',
      );
    }
  }

  @override
  void dispose() {
    _backendUrl.dispose();
    for (final c in _paths.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Persist-feedback: only an actual value change reports 已保存, so tapping
  /// through fields doesn't spam confirmations.
  Future<void> _saveIfChanged({
    required String before,
    required String after,
    required Future<void> Function() save,
  }) async {
    if (before.trim() == after.trim()) return;
    await save();
    _confirmSaved();
  }

  void _confirmSaved() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(content: Text('已保存'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<ConfigStore>();
    final themeController = context.watch<AppThemeController>();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('设置', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _section(theme, '外观', [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ThemeModeSelector(
                          value: themeController.themeMode,
                          onChanged: (mode) {
                            themeController.setThemeMode(mode);
                            _confirmSaved();
                          },
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _section(theme, '后端服务', [_backendUrlField(store)]),
                  const SizedBox(height: 12),
                  _section(theme, 'SSH 工具', [
                    for (final t in SshToolRegistry.all)
                      _pathField(
                        t.displayName,
                        _paths[t.id]!,
                        (v) => _saveIfChanged(
                          before:
                              store.config.sshTools.executablePaths[t.id] ?? '',
                          after: v,
                          save: () => store.setSshExecutablePath(t.id, v),
                        ),
                      ),
                    const SizedBox(height: 4),
                    _toolDropdown(
                      '默认终端',
                      SshToolRegistry.all
                          .where((t) => t.kind == SshToolKind.terminal)
                          .toList(),
                      store.defaultTerminalToolId,
                      (id) => _saveIfChanged(
                        before: store.defaultTerminalToolId ?? '',
                        after: id ?? '',
                        save: () => store.setDefaultTerminalToolId(id),
                      ),
                    ),
                    _toolDropdown(
                      '默认 SFTP',
                      SshToolRegistry.all
                          .where((t) => t.kind == SshToolKind.sftp)
                          .toList(),
                      store.defaultSftpToolId,
                      (id) => _saveIfChanged(
                        before: store.defaultSftpToolId ?? '',
                        after: id ?? '',
                        save: () => store.setDefaultSftpToolId(id),
                      ),
                    ),
                    _passwordModeDropdown(store),
                  ]),
                  const SizedBox(height: 12),
                  _section(theme, '数据库工具', [
                    for (final t in DbToolRegistry.all)
                      _pathField(
                        t.displayName,
                        _paths[t.id]!,
                        (v) => _saveIfChanged(
                          before:
                              store.config.dbTools.executablePaths[t.id] ?? '',
                          after: v,
                          save: () => store.setDbExecutablePath(t.id, v),
                        ),
                      ),
                    const SizedBox(height: 4),
                    _dbToolDropdown(
                      '默认数据库工具',
                      DbToolRegistry.all,
                      store.defaultDbToolId,
                      (id) => _saveIfChanged(
                        before: store.defaultDbToolId ?? '',
                        after: id ?? '',
                        save: () => store.setDefaultDbToolId(id),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(ThemeData theme, String title, List<Widget> children) {
    final tokens = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.cardBg,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(color: tokens.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _backendUrlField(ConfigStore store) {
    final locked = store.backendUrlLocked;
    Future<void> save(String value) => _saveIfChanged(
      before: store.config.backendBaseUrl ?? '',
      after: value,
      save: () => store.setBackendBaseUrl(value),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: _backendUrl,
        enabled: !locked,
        decoration: InputDecoration(
          labelText: '后端地址',
          hintText: 'http://localhost:8080',
          helperText: locked ? '由环境变量 ENV_DASHBOARD_BACKEND_URL 控制' : '需重启生效',
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onSubmitted: save,
        onTapOutside: (_) {
          FocusManager.instance.primaryFocus?.unfocus();
          if (!locked) save(_backendUrl.text);
        },
      ),
    );
  }

  Widget _pathField(
    String label,
    TextEditingController controller,
    Future<void> Function(String) onSave,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: '$label 可执行路径',
          hintText: '留空则自动探测默认安装位置',
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onSubmitted: onSave,
        onTapOutside: (_) {
          FocusManager.instance.primaryFocus?.unfocus();
          onSave(controller.text);
        },
      ),
    );
  }

  Widget _toolDropdown(
    String label,
    List<SshTool> tools,
    String? value,
    void Function(String?) onChanged,
  ) {
    final ids = tools.map((t) => t.id).toSet();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DropdownButtonFormField<String?>(
        initialValue: ids.contains(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('自动')),
          for (final t in tools)
            DropdownMenuItem<String?>(value: t.id, child: Text(t.displayName)),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _dbToolDropdown(
    String label,
    List<DbTool> tools,
    String? value,
    void Function(String?) onChanged,
  ) {
    final ids = tools.map((t) => t.id).toSet();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DropdownButtonFormField<String?>(
        initialValue: ids.contains(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('自动')),
          for (final t in tools)
            DropdownMenuItem<String?>(value: t.id, child: Text(t.displayName)),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _passwordModeDropdown(ConfigStore store) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DropdownButtonFormField<PasswordMode>(
        initialValue: store.passwordMode,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: '密码传递',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: const [
          DropdownMenuItem(value: PasswordMode.argv, child: Text('命令行参数')),
          DropdownMenuItem(value: PasswordMode.clipboard, child: Text('剪贴板')),
        ],
        onChanged: (m) {
          if (m != null && m != store.passwordMode) {
            store.setPasswordMode(m);
            _confirmSaved();
          }
        },
      ),
    );
  }
}
