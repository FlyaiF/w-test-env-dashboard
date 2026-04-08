import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/config_service.dart';
import '../../config/feature_profile.dart';
import '../../sidecar/sidecar_client.dart';
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

  bool _testing = false;
  bool _saving = false;
  String? _testResult;

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
    if (mounted) setState(() {});
  }

  AppConfig _buildConfig() {
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
    );
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });

    final config = _buildConfig();
    final sidecar = context.read<SidecarManager>();

    try {
      if (!sidecar.connected) {
        setState(() => _testResult = '后端服务未连接，请先保存并连接');
        return;
      }
      final client = SidecarClient(sidecar.baseUrl);
      final msg = await client.testConnection(config.dsn);
      setState(() => _testResult = msg);
    } catch (e) {
      setState(() => _testResult = '连接失败: $e');
    } finally {
      setState(() => _testing = false);
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

      if (mounted) {
        final sidecar = context.read<SidecarManager>();
        await sidecar.restart(config.dsn);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                sidecar.connected
                    ? '保存成功，已重新连接'
                    : '保存成功，但连接失败: ${sidecar.error}',
              ),
            ),
          );
        }
      }
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('设置', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 24),

          // Oracle section
          Card(
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
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _hostCtrl,
                          decoration: const InputDecoration(
                            labelText: '主机地址',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: _portCtrl,
                          decoration: const InputDecoration(
                            labelText: '端口',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _serviceCtrl,
                    decoration: const InputDecoration(
                      labelText: '服务名 (Service Name)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _userCtrl,
                          decoration: const InputDecoration(
                            labelText: '用户名',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _passCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: '密码',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _testing ? null : _testConnection,
                        icon: _testing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.wifi_tethering),
                        label: const Text('测试连接'),
                      ),
                      if (_testResult != null) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _testResult!,
                            style: TextStyle(
                              color: _testResult!.contains('失败')
                                  ? Colors.red
                                  : Colors.green,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // SSH section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '默认 SSH 配置',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _sshUserCtrl,
                          decoration: const InputDecoration(
                            labelText: '默认用户名',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _sshPassCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: '默认密码',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Feature profile section (only shown for named profiles)
          Builder(builder: (context) {
            final profile = context.watch<FeatureProfile>();
            if (!profile.isNamedProfile) return const SizedBox.shrink();
            return Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用全部功能'),
                  subtitle: const Text('显示所有功能模块，而非仅当前模式对应的功能'),
                  value: profile.showAll,
                  onChanged: (v) async {
                    profile.showAll = v;
                    final config = _buildConfig();
                    config.showAllFeatures = v;
                    await ConfigService.save(config);
                  },
                ),
              ),
            );
          }),
          const SizedBox(height: 24),

          // Save button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving ? null : _saveAndReconnect,
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
          ),
        ],
      ),
    );
  }
}
