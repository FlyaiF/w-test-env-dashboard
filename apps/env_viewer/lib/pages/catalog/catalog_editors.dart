import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api/dto/component_input.dart';
import '../../api/dto/environment_input.dart';
import '../../catalog/catalog_acl.dart';
import '../../catalog/environment_view.dart';

/// Modal editors for Environment Catalog curation (slice 03). Each returns the
/// edited write-input on save, or null when the user cancels. They produce
/// backend-shaped inputs ([EnvironmentInput] / [ComponentInput]) via the
/// product's ubiquitous language — role/probe pickers speak localized labels but
/// carry the backend enum codes, so the anti-corruption boundary stays intact.

/// Edit an Environment's own fields (name, memo). Pass [existing] to edit, omit
/// to create. Components are curated separately, so this form never touches them.
Future<EnvironmentInput?> showEnvironmentEditor(
  BuildContext context, {
  EnvironmentView? existing,
}) {
  return showDialog<EnvironmentInput>(
    context: context,
    builder: (_) => _EnvironmentEditorDialog(existing: existing),
  );
}

/// Edit one Component. Pass [existing] to edit, omit to create.
Future<ComponentInput?> showComponentEditor(
  BuildContext context, {
  ComponentView? existing,
}) {
  return showDialog<ComponentInput>(
    context: context,
    builder: (_) => _ComponentEditorDialog(existing: existing),
  );
}

class _EnvironmentEditorDialog extends StatefulWidget {
  final EnvironmentView? existing;

  const _EnvironmentEditorDialog({this.existing});

  @override
  State<_EnvironmentEditorDialog> createState() =>
      _EnvironmentEditorDialogState();
}

class _EnvironmentEditorDialogState extends State<_EnvironmentEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _memo;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _memo = TextEditingController(text: widget.existing?.memo ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _memo.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      EnvironmentInput(
        name: _name.text.trim(),
        memo: _blankToNull(_memo.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? '编辑环境' : '新建环境'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: '名称 *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '请输入环境名称' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _memo,
                decoration: const InputDecoration(labelText: '备注'),
                maxLines: 2,
              ),
            ],
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

class _ComponentEditorDialog extends StatefulWidget {
  final ComponentView? existing;

  const _ComponentEditorDialog({this.existing});

  @override
  State<_ComponentEditorDialog> createState() => _ComponentEditorDialogState();
}

class _ComponentEditorDialogState extends State<_ComponentEditorDialog> {
  static final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');

  final _formKey = GlobalKey<FormState>();
  late String _role;
  String? _versionProbe;
  late final TextEditingController _version;
  late final TextEditingController _deployTime;
  late final TextEditingController _logLocation;
  late final TextEditingController _listenPort;
  late final TextEditingController _protocol;
  late final TextEditingController _url;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _role = e?.roleCode ?? CatalogAcl.roleCodes.first;
    _versionProbe = e?.versionProbeCode;
    _version = TextEditingController(text: e?.version ?? '');
    _deployTime = TextEditingController(
      text: e?.deployTime == null ? '' : _dateFmt.format(e!.deployTime!.toLocal()),
    );
    _logLocation = TextEditingController(text: e?.logLocation ?? '');
    _listenPort = TextEditingController(text: e?.listenPort?.toString() ?? '');
    _protocol = TextEditingController(text: e?.protocol ?? '');
    _url = TextEditingController(text: e?.url ?? '');
  }

  @override
  void dispose() {
    _version.dispose();
    _deployTime.dispose();
    _logLocation.dispose();
    _listenPort.dispose();
    _protocol.dispose();
    _url.dispose();
    super.dispose();
  }

  DateTime? _parseDeployTime() {
    final text = _deployTime.text.trim();
    if (text.isEmpty) return null;
    return _dateFmt.parseStrict(text);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final port = _listenPort.text.trim();
    Navigator.of(context).pop(
      ComponentInput(
        role: _role,
        version: _blankToNull(_version.text),
        deployTime: _parseDeployTime(),
        logLocation: _blankToNull(_logLocation.text),
        listenPort: port.isEmpty ? null : int.parse(port),
        protocol: _blankToNull(_protocol.text),
        url: _blankToNull(_url.text),
        versionProbe: _versionProbe,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? '编辑组件' : '新建组件'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: '角色 *'),
                  items: [
                    for (final code in CatalogAcl.roleCodes)
                      DropdownMenuItem<String>(
                        value: code,
                        child: Text(CatalogAcl.roleLabel(code)),
                      ),
                  ],
                  onChanged: (v) => setState(() => _role = v ?? _role),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _versionProbe,
                  decoration: const InputDecoration(labelText: '版本探测'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('未设置'),
                    ),
                    for (final code in CatalogAcl.versionProbeCodes)
                      DropdownMenuItem<String?>(
                        value: code,
                        child: Text(CatalogAcl.versionProbeLabel(code)),
                      ),
                  ],
                  onChanged: (v) => setState(() => _versionProbe = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _version,
                  decoration: const InputDecoration(labelText: '版本'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _deployTime,
                  decoration: const InputDecoration(
                    labelText: '部署时间',
                    hintText: 'yyyy-MM-dd HH:mm',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    try {
                      _dateFmt.parseStrict(v.trim());
                      return null;
                    } on FormatException {
                      return '格式应为 yyyy-MM-dd HH:mm';
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _protocol,
                  decoration: const InputDecoration(labelText: '协议'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _listenPort,
                  decoration: const InputDecoration(labelText: '监听端口'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final n = int.tryParse(v.trim());
                    if (n == null || n < 0 || n > 65535) return '端口应为 0-65535';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _url,
                  decoration: const InputDecoration(labelText: '访问地址'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _logLocation,
                  decoration: const InputDecoration(labelText: '日志位置'),
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

String? _blankToNull(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
