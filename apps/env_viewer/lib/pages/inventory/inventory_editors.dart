import 'package:flutter/material.dart';

import '../../api/dto/database_input.dart';
import '../../api/dto/server_input.dart';
import '../../inventory/inventory_acl.dart';
import '../../inventory/inventory_view.dart';

const _serverOsCodes = ['LINUX', 'WINDOWS'];
const _databaseTypeCodes = ['ORACLE', 'DAMENG', 'OCEANBASE', 'OTHER'];

/// What the Server editor hands back: the non-secret metadata payload, plus an
/// optional write-only [secret]. A null secret means "leave the stored secret
/// untouched"; a non-null one is transmitted once to the broker and dropped.
class ServerEditorResult {
  final ServerInput input;
  final String? secret;

  const ServerEditorResult(this.input, this.secret);
}

/// What the Database editor hands back; mirrors [ServerEditorResult].
class DatabaseEditorResult {
  final DatabaseInput input;
  final String? secret;

  const DatabaseEditorResult(this.input, this.secret);
}

/// Opens the Server editor. The metadata payload stays non-secret; the password
/// field is write-only — the current secret is never fetched or displayed, and
/// leaving the field empty keeps it unchanged (ADR-0005).
Future<ServerEditorResult?> showServerEditor(
  BuildContext context, {
  ServerView? existing,
}) {
  return showDialog<ServerEditorResult>(
    context: context,
    builder: (_) => _ServerEditorDialog(existing: existing),
  );
}

class _ServerEditorDialog extends StatefulWidget {
  final ServerView? existing;

  const _ServerEditorDialog({this.existing});

  @override
  State<_ServerEditorDialog> createState() => _ServerEditorDialogState();
}

class _ServerEditorDialogState extends State<_ServerEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _host;
  late final TextEditingController _sshHost;
  late final TextEditingController _sshPort;
  late final TextEditingController _sshUsername;
  late final TextEditingController _password;
  late String _os;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _host = TextEditingController(text: existing?.host ?? '');
    _sshHost = TextEditingController(text: existing?.sshHost ?? '');
    _sshPort = TextEditingController(text: existing?.sshPort?.toString() ?? '');
    _sshUsername = TextEditingController(text: existing?.sshUsername ?? '');
    // Write-only: never pre-filled, empty means "keep the stored secret".
    _password = TextEditingController();
    _os = _blankToNull(existing?.os) ?? _serverOsCodes.first;
  }

  @override
  void dispose() {
    _host.dispose();
    _sshHost.dispose();
    _sshPort.dispose();
    _sshUsername.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final sshHost = _blankToNull(_sshHost.text);
    final sshPortText = _sshPort.text.trim();
    final sshUsername = _blankToNull(_sshUsername.text);
    final hasSsh =
        sshHost != null || sshPortText.isNotEmpty || sshUsername != null;
    final input = ServerInput(
      host: _host.text.trim(),
      os: _os,
      ssh: hasSsh
          ? SshAccessInput(
              host: sshHost,
              port: sshPortText.isEmpty ? null : int.parse(sshPortText),
              username: sshUsername,
            )
          : null,
    );
    Navigator.of(context).pop(
      ServerEditorResult(input, _secretOrNull(_password.text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final osCodes = <String>{..._serverOsCodes, _os}.toList();
    return AlertDialog(
      title: Text(_isEdit ? '编辑服务器' : '新建服务器'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const ValueKey('server-host-field'),
                  controller: _host,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '主机地址 *'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请输入主机地址' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const ValueKey('server-os-field'),
                  initialValue: _os,
                  decoration: const InputDecoration(labelText: '操作系统 *'),
                  items: [
                    for (final code in osCodes)
                      DropdownMenuItem(
                        value: code,
                        child: Text(InventoryAcl.serverOsLabel(code)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _os = value);
                  },
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'SSH 信息（可选）',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const ValueKey('server-ssh-host-field'),
                  controller: _sshHost,
                  decoration: const InputDecoration(labelText: 'SSH 主机'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('server-ssh-port-field'),
                  controller: _sshPort,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'SSH 端口'),
                  validator: _portValidator,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('server-ssh-username-field'),
                  controller: _sshUsername,
                  decoration: const InputDecoration(labelText: 'SSH 用户名'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('server-password-field'),
                  controller: _password,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'SSH 密码',
                    hintText: _isEdit ? '留空则不修改密码' : '可选，创建后也可设置',
                    helperText: _isEdit
                        ? (widget.existing!.hasSecret ? '当前已设置密码' : '当前未设置密码')
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

/// Opens the Database editor. The metadata payload stays non-secret; the
/// password field is write-only — the current secret is never fetched or
/// displayed, and leaving the field empty keeps it unchanged (ADR-0005).
Future<DatabaseEditorResult?> showDatabaseEditor(
  BuildContext context, {
  DatabaseView? existing,
}) {
  return showDialog<DatabaseEditorResult>(
    context: context,
    builder: (_) => _DatabaseEditorDialog(existing: existing),
  );
}

class _DatabaseEditorDialog extends StatefulWidget {
  final DatabaseView? existing;

  const _DatabaseEditorDialog({this.existing});

  @override
  State<_DatabaseEditorDialog> createState() => _DatabaseEditorDialogState();
}

class _DatabaseEditorDialogState extends State<_DatabaseEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _role;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _serviceName;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late String _type;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _role = TextEditingController(text: existing?.role ?? '');
    _host = TextEditingController(text: existing?.host ?? '');
    _port = TextEditingController(text: existing?.port?.toString() ?? '');
    _serviceName = TextEditingController(text: existing?.serviceName ?? '');
    _username = TextEditingController(text: existing?.username ?? '');
    // Write-only: never pre-filled, empty means "keep the stored secret".
    _password = TextEditingController();
    _type = _blankToNull(existing?.type) ?? _databaseTypeCodes.first;
  }

  @override
  void dispose() {
    _role.dispose();
    _host.dispose();
    _port.dispose();
    _serviceName.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final host = _blankToNull(_host.text);
    final portText = _port.text.trim();
    final serviceName = _blankToNull(_serviceName.text);
    final username = _blankToNull(_username.text);
    final hasConnection =
        host != null ||
        portText.isNotEmpty ||
        serviceName != null ||
        username != null;
    final input = DatabaseInput(
      role: _blankToNull(_role.text),
      type: _type,
      connection: hasConnection
          ? DatabaseConnectionInput(
              host: host,
              port: portText.isEmpty ? null : int.parse(portText),
              serviceName: serviceName,
              username: username,
            )
          : null,
    );
    Navigator.of(context).pop(
      DatabaseEditorResult(input, _secretOrNull(_password.text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final typeCodes = <String>{..._databaseTypeCodes, _type}.toList();
    return AlertDialog(
      title: Text(_isEdit ? '编辑数据库' : '新建数据库'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const ValueKey('database-role-field'),
                  controller: _role,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '用途',
                    hintText: 'business / intermediate',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const ValueKey('database-type-field'),
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: '数据库类型 *'),
                  items: [
                    for (final code in typeCodes)
                      DropdownMenuItem(
                        value: code,
                        child: Text(InventoryAcl.databaseTypeLabel(code)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _type = value);
                  },
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '连接信息（可选）',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const ValueKey('database-host-field'),
                  controller: _host,
                  decoration: const InputDecoration(labelText: '主机地址'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('database-port-field'),
                  controller: _port,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '端口'),
                  validator: _portValidator,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('database-service-field'),
                  controller: _serviceName,
                  decoration: const InputDecoration(labelText: '服务名 / 数据库名'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('database-username-field'),
                  controller: _username,
                  decoration: const InputDecoration(labelText: '用户名'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('database-password-field'),
                  controller: _password,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: '密码',
                    hintText: _isEdit ? '留空则不修改密码' : '可选，创建后也可设置',
                    helperText: _isEdit
                        ? (widget.existing!.hasSecret ? '当前已设置密码' : '当前未设置密码')
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

String? _portValidator(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final port = int.tryParse(text);
  if (port == null || port < 1 || port > 65535) return '端口应为 1-65535';
  return null;
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// Unlike [_blankToNull], keeps the secret verbatim (passwords may contain
/// meaningful whitespace); only an effectively empty entry means "unchanged".
String? _secretOrNull(String value) => value.trim().isEmpty ? null : value;
