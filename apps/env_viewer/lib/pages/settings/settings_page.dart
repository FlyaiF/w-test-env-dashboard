import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart'
    show AppThemeController, ThemeModeSelector;

import '../../config/config_service.dart';
import '../../services/ssh_tools/ssh_tool.dart';
import '../../services/ssh_tools/ssh_tool_registry.dart';
import '../../sidecar/sidecar_manager.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  final _serviceCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _sshUserCtrl = TextEditingController();
  final _sshPassCtrl = TextEditingController();
  final Map<String, TextEditingController> _toolPathCtrls = {};

  String? _defaultTerminalToolId;
  String? _defaultSftpToolId;
  String _passwordMode = 'argv';

  bool _testing = false;
  bool _saving = false;
  bool? _testPassed;
  String? _testResult;

  bool get _isBusy => _testing || _saving;
  bool get _hasRequiredOracle =>
      _hostCtrl.text.trim().isNotEmpty &&
      _serviceCtrl.text.trim().isNotEmpty &&
      _userCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = await ConfigService.load();
    _hostCtrl.text = config.oracle.host;
    _portCtrl.text = config.oracle.port.toString();
    _serviceCtrl.text = config.oracle.service;
    _userCtrl.text = config.oracle.username;
    _passCtrl.text = config.oracle.password;
    _sshUserCtrl.text = config.ssh.defaultUsername;
    _sshPassCtrl.text = config.ssh.defaultPassword;
    _defaultTerminalToolId = config.sshTools.defaultTerminalToolId;
    _defaultSftpToolId = config.sshTools.defaultSftpToolId;
    _passwordMode = config.sshTools.passwordMode;
    for (final tool in SshToolRegistry.availableOnPlatform) {
      final ctrl = _toolPathCtrls.putIfAbsent(
        tool.id,
        TextEditingController.new,
      );
      ctrl.text = config.sshTools.executablePaths[tool.id] ?? '';
    }
    if (mounted) setState(() {});
  }

  AppConfig _buildConfig() {
    final paths = <String, String>{};
    _toolPathCtrls.forEach((id, ctrl) {
      final v = ctrl.text.trim();
      if (v.isNotEmpty) paths[id] = v;
    });
    return AppConfig(
      oracle: OracleConfig(
        host: _hostCtrl.text.trim(),
        port: int.tryParse(_portCtrl.text.trim()) ?? 1521,
        service: _serviceCtrl.text.trim(),
        username: _userCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      ),
      ssh: SshConfig(
        defaultUsername: _sshUserCtrl.text.trim(),
        defaultPassword: _sshPassCtrl.text.trim(),
      ),
      sshTools: SshToolsConfig(
        defaultTerminalToolId: _defaultTerminalToolId,
        defaultSftpToolId: _defaultSftpToolId,
        executablePaths: paths,
        passwordMode: _passwordMode,
      ),
    );
  }

  void _markConnectionChanged(String _) {
    setState(() {
      _testPassed = null;
      _testResult = null;
    });
  }

  Future<void> _testConnection() async {
    final config = _buildConfig();
    if (!config.isOracleConfigured) {
      setState(() {
        _testPassed = false;
        _testResult = '请先填写主机、服务名和用户名';
      });
      return;
    }

    setState(() {
      _testing = true;
      _testPassed = null;
      _testResult = null;
    });

    try {
      final msg = await context.read<SidecarManager>().testConnection(
        config.dsn,
      );
      if (!mounted) return;
      setState(() {
        _testPassed = true;
        _testResult = msg == 'connection successful' ? '连接成功' : msg;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testPassed = false;
        _testResult = '连接失败: $e';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _saveAndReconnect() async {
    final config = _buildConfig();
    if (!config.isOracleConfigured) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填写数据库连接信息')));
      return;
    }

    setState(() => _saving = true);

    try {
      await ConfigService.save(config);

      if (!mounted) return;
      final sidecar = context.read<SidecarManager>();
      await sidecar.restart(config.dsn);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sidecar.connected ? '保存成功，已重新连接' : '保存成功，但连接失败: ${sidecar.error}',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _serviceCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _sshUserCtrl.dispose();
    _sshPassCtrl.dispose();
    for (final ctrl in _toolPathCtrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sidecar = context.watch<SidecarManager>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('设置', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          _ConnectionStatusCard(
            connected: sidecar.connected,
            error: sidecar.error,
            testPassed: _testPassed,
            testResult: _testResult,
          ),
          const SizedBox(height: 16),
          _buildAppearanceSection(),
          const SizedBox(height: 16),
          _buildOracleSection(),
          const SizedBox(height: 16),
          _buildSshSection(),
          const SizedBox(height: 16),
          _buildSshToolsSection(),
          const SizedBox(height: 24),
          _buildActionBar(),
        ],
      ),
    );
  }

  Widget _buildAppearanceSection() {
    final themeController = context.watch<AppThemeController>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('外观', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ThemeModeSelector(
              value: themeController.themeMode,
              onChanged: themeController.setThemeMode,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOracleSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Oracle 数据库连接',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 680;
                final host = _field(
                  controller: _hostCtrl,
                  label: '主机地址',
                  icon: Icons.dns_outlined,
                  onChanged: _markConnectionChanged,
                );
                final port = _field(
                  controller: _portCtrl,
                  label: '端口',
                  icon: Icons.numbers,
                  keyboardType: TextInputType.number,
                  onChanged: _markConnectionChanged,
                );
                if (stacked) {
                  return Column(
                    children: [host, const SizedBox(height: 12), port],
                  );
                }
                return Row(
                  children: [
                    Expanded(flex: 3, child: host),
                    const SizedBox(width: 12),
                    Expanded(child: port),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            _field(
              controller: _serviceCtrl,
              label: '服务名 (Service Name)',
              icon: Icons.storage_outlined,
              onChanged: _markConnectionChanged,
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 680;
                final user = _field(
                  controller: _userCtrl,
                  label: '用户名',
                  icon: Icons.person_outline,
                  onChanged: _markConnectionChanged,
                );
                final pass = _field(
                  controller: _passCtrl,
                  label: '密码',
                  icon: Icons.key_outlined,
                  obscureText: true,
                  onChanged: _markConnectionChanged,
                );
                if (stacked) {
                  return Column(
                    children: [user, const SizedBox(height: 12), pass],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: user),
                    const SizedBox(width: 12),
                    Expanded(child: pass),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSshSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('默认 SSH 配置', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 680;
                final user = _field(
                  controller: _sshUserCtrl,
                  label: '默认用户名',
                  icon: Icons.person_outline,
                );
                final pass = _field(
                  controller: _sshPassCtrl,
                  label: '默认密码',
                  icon: Icons.key_outlined,
                  obscureText: true,
                );
                if (stacked) {
                  return Column(
                    children: [user, const SizedBox(height: 12), pass],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: user),
                    const SizedBox(width: 12),
                    Expanded(child: pass),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSshToolsSection() {
    final terminals = SshToolRegistry.availableFor(SshToolKind.terminal);
    final sftps = SshToolRegistry.availableFor(SshToolKind.sftp);
    final platformTools = SshToolRegistry.availableOnPlatform;
    if (platformTools.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SSH 外部工具', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '配置默认连接工具与可执行文件路径，用于从仪表板一键连接目标主机。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 680;
                final term = _toolDropdown(
                  label: '默认终端工具',
                  value: _defaultTerminalToolId,
                  tools: terminals,
                  onChanged: (v) => setState(() => _defaultTerminalToolId = v),
                );
                final sftp = _toolDropdown(
                  label: '默认 SFTP 工具',
                  value: _defaultSftpToolId,
                  tools: sftps,
                  onChanged: (v) => setState(() => _defaultSftpToolId = v),
                );
                if (stacked) {
                  return Column(
                    children: [term, const SizedBox(height: 12), sftp],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: term),
                    const SizedBox(width: 12),
                    Expanded(child: sftp),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Text('密码传递方式', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'argv', label: Text('命令行参数')),
                ButtonSegment(value: 'clipboard', label: Text('复制到剪贴板')),
              ],
              selected: {_passwordMode},
              onSelectionChanged: (s) =>
                  setState(() => _passwordMode = s.first),
            ),
            const SizedBox(height: 4),
            Text(
              'macOS 终端始终使用剪贴板模式（系统 ssh 不支持命令行密码）。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 16),
            Text('可执行文件路径', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            for (final tool in platformTools) ...[
              _toolPathField(tool),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _toolDropdown({
    required String label,
    required String? value,
    required List<SshTool> tools,
    required ValueChanged<String?> onChanged,
  }) {
    final ids = tools.map((t) => t.id).toSet();
    return DropdownButtonFormField<String?>(
      initialValue: ids.contains(value) ? value : null,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('未设置')),
        for (final tool in tools)
          DropdownMenuItem<String?>(
            value: tool.id,
            child: Text(tool.displayName),
          ),
      ],
      onChanged: tools.isEmpty ? null : onChanged,
    );
  }

  Widget _toolPathField(SshTool tool) {
    final ctrl = _toolPathCtrls.putIfAbsent(tool.id, TextEditingController.new);
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: tool.displayName,
        hintText: '留空使用默认安装路径',
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: IconButton(
          tooltip: '选择文件',
          icon: const Icon(Icons.folder_open),
          onPressed: () => _pickToolPath(tool),
        ),
      ),
    );
  }

  Future<void> _pickToolPath(SshTool tool) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择 ${tool.displayName} 可执行文件',
    );
    if (result == null) return;
    final path = result.files.single.path;
    if (path == null) return;
    setState(() {
      _toolPathCtrls[tool.id]!.text = path;
    });
  }

  Widget _buildActionBar() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StepChip(
                    icon: Icons.edit_outlined,
                    label: '填写数据库信息',
                    active: !_hasRequiredOracle,
                  ),
                  _StepChip(
                    icon: Icons.wifi_tethering,
                    label: '测试连接',
                    active: _testPassed != true,
                  ),
                  _StepChip(
                    icon: Icons.sync,
                    label: '保存并同步',
                    active: _testPassed == true,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            OutlinedButton.icon(
              onPressed: _isBusy ? null : _testConnection,
              icon: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering),
              label: const Text('测试连接'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _isBusy ? null : _saveAndReconnect,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save),
              label: const Text('保存并重新连接'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

class _ConnectionStatusCard extends StatelessWidget {
  final bool connected;
  final String? error;
  final bool? testPassed;
  final String? testResult;

  const _ConnectionStatusCard({
    required this.connected,
    required this.error,
    required this.testPassed,
    required this.testResult,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = connected
        ? Colors.green
        : error == null
        ? colorScheme.outline
        : colorScheme.error;
    final statusText = connected
        ? '后端已连接'
        : error == null
        ? '后端未连接'
        : '后端连接失败';
    final testColor = testPassed == null
        ? colorScheme.outline
        : testPassed!
        ? Colors.green
        : colorScheme.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              connected ? Icons.cloud_done : Icons.cloud_off,
              color: statusColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(statusText, style: theme.textTheme.titleSmall),
                  if (error != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.error,
                      ),
                    ),
                  ],
                  if (testResult != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          testPassed == true
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          size: 16,
                          color: testColor,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            testResult!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: testColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;

  const _StepChip({
    required this.icon,
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(
        icon,
        size: 16,
        color: active ? colorScheme.primary : colorScheme.outline,
      ),
      label: Text(label),
      backgroundColor: active
          ? colorScheme.primaryContainer.withValues(alpha: 0.35)
          : colorScheme.surfaceContainerLow,
    );
  }
}
