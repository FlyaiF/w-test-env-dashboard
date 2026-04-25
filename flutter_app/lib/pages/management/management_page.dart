import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/env_info.dart';
import '../../models/runtime_env_collection.dart';
import '../../services/env_service.dart';

class ManagementPage extends StatefulWidget {
  const ManagementPage({super.key});

  @override
  State<ManagementPage> createState() => _ManagementPageState();
}

class _ManagementPageState extends State<ManagementPage> {
  final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EnvService>().load();
    });
  }

  void _showForm({EnvInfo? env}) async {
    final result = await showDialog<EnvInfo>(
      context: context,
      builder: (ctx) => _EnvFormDialog(env: env),
    );
    if (result == null || !mounted) return;

    final service = context.read<EnvService>();
    try {
      if (env == null) {
        await service.createEnv(result);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('创建成功')));
        }
      } else {
        await service.updateEnv(env.eNo, result.toJson());
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('更新成功')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('操作失败: $e')));
      }
    }
  }

  void _deleteEnv(EnvInfo env) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除环境 "${env.eName ?? ""}" (编号: ${env.eNo}) 吗?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await context.read<EnvService>().deleteEnv(env.eNo);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已删除')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
      }
    }
  }

  void _collectRuntimeInfo() async {
    final service = context.read<EnvService>();
    try {
      final results = await service.collectRuntimePreview();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => _RuntimeDiffDialog(results: results),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('采集失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<EnvService>();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text('环境管理', style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: service.collecting ? null : _collectRuntimeInfo,
                icon: const Icon(Icons.compare_arrows),
                label: const Text('采集运行库信息'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _showForm(),
                icon: const Icon(Icons.add),
                label: const Text('新增环境'),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: service.syncing ? null : service.sync,
                tooltip: '从远程刷新',
              ),
            ],
          ),
        ),
        if (service.loading ||
            service.syncing ||
            service.collecting ||
            service.publishingCollected)
          const LinearProgressIndicator(),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                columnSpacing: 16,
                headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                columns: const [
                  DataColumn(label: Text('编号')),
                  DataColumn(label: Text('环境别名')),
                  DataColumn(label: Text('业务库')),
                  DataColumn(label: Text('中间库')),
                  DataColumn(label: Text('访问地址')),
                  DataColumn(label: Text('版本号')),
                  DataColumn(label: Text('更新时间')),
                  DataColumn(label: Text('Web服务')),
                  DataColumn(label: Text('日志路径')),
                  DataColumn(label: Text('备注')),
                  DataColumn(label: Text('操作')),
                ],
                rows: service.envs
                    .map(
                      (e) => DataRow(
                        cells: [
                          DataCell(Text('${e.eNo}')),
                          DataCell(Text(e.eName ?? '-')),
                          DataCell(
                            Text(
                              e.eYwdb ?? '-',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DataCell(
                            Text(
                              e.eZjdb ?? '-',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 200),
                              child: Text(
                                e.eUrl ?? '-',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(Text(e.eVersion ?? '-')),
                          DataCell(
                            Text(
                              e.eUpdatetime != null
                                  ? _dateFmt.format(e.eUpdatetime!.toLocal())
                                  : '-',
                            ),
                          ),
                          DataCell(Text(e.eWebserveraddr ?? '-')),
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 180),
                              child: Text(
                                e.eWeblogpath ?? '-',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 120),
                              child: Text(
                                e.eMemo ?? '-',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18),
                                  tooltip: '编辑',
                                  onPressed: () => _showForm(env: e),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                  tooltip: '删除',
                                  onPressed: () => _deleteEnv(e),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RuntimeDiffDialog extends StatefulWidget {
  final List<RuntimeEnvCollectionResult> results;

  const _RuntimeDiffDialog({required this.results});

  @override
  State<_RuntimeDiffDialog> createState() => _RuntimeDiffDialogState();
}

class _RuntimeDiffDialogState extends State<_RuntimeDiffDialog> {
  final _dateFmt = DateFormat('yyyy-MM-dd HH:mm:ss');
  late final Set<int> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.results
        .where((e) => e.isPublishable)
        .map((e) => e.eNo)
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final changed = widget.results.where((e) => e.status == 'changed').length;
    final skipped = widget.results.where((e) => e.status == 'skipped').length;
    final failed = widget.results.where((e) => e.status == 'failed').length;
    final unchanged = widget.results
        .where((e) => e.status == 'unchanged')
        .length;
    final selectedItems = widget.results
        .where((e) => _selected.contains(e.eNo) && e.isPublishable)
        .toList();

    return AlertDialog(
      title: const Text('运行库信息差异'),
      content: SizedBox(
        width: 980,
        height: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                _chip('变更 $changed', Colors.orange),
                _chip('无变化 $unchanged', Colors.green),
                _chip('跳过 $skipped', Colors.grey),
                _chip('失败 $failed', Colors.red),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    columnSpacing: 14,
                    columns: const [
                      DataColumn(label: Text('发布')),
                      DataColumn(label: Text('编号')),
                      DataColumn(label: Text('环境')),
                      DataColumn(label: Text('状态')),
                      DataColumn(label: Text('当前版本')),
                      DataColumn(label: Text('采集版本')),
                      DataColumn(label: Text('当前更新时间')),
                      DataColumn(label: Text('采集更新时间')),
                      DataColumn(label: Text('子系统版本')),
                      DataColumn(label: Text('说明')),
                    ],
                    rows: widget.results.map(_row).toList(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          onPressed: selectedItems.isEmpty
              ? null
              : () => _publish(selectedItems),
          icon: const Icon(Icons.publish),
          label: Text('发布 ${selectedItems.length} 项变更'),
        ),
      ],
    );
  }

  DataRow _row(RuntimeEnvCollectionResult result) {
    final publishable = result.isPublishable;
    return DataRow(
      selected: _selected.contains(result.eNo),
      cells: [
        DataCell(
          Checkbox(
            value: _selected.contains(result.eNo),
            onChanged: publishable
                ? (value) {
                    setState(() {
                      if (value == true) {
                        _selected.add(result.eNo);
                      } else {
                        _selected.remove(result.eNo);
                      }
                    });
                  }
                : null,
          ),
        ),
        DataCell(Text('${result.eNo}')),
        DataCell(Text(result.eName ?? '-')),
        DataCell(_status(result.status)),
        DataCell(
          _diffText(result.current.eVersion, result.diff.versionChanged),
        ),
        DataCell(
          _diffText(result.fresh?.systemVersion, result.diff.versionChanged),
        ),
        DataCell(
          _diffText(
            _formatDate(result.current.eUpdatetime),
            result.diff.updateTimeChanged,
          ),
        ),
        DataCell(
          _diffText(
            _formatDate(result.fresh?.beginTime),
            result.diff.updateTimeChanged,
          ),
        ),
        DataCell(Text(result.fresh?.subsystemVer ?? '-')),
        DataCell(_messageCell(result)),
      ],
    );
  }

  Widget _messageCell(RuntimeEnvCollectionResult result) {
    final message = result.error ?? (result.status == 'changed' ? '待发布' : '-');
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Tooltip(
              message: message,
              child: Text(message, overflow: TextOverflow.ellipsis),
            ),
          ),
          if (result.error != null)
            IconButton(
              tooltip: '复制错误',
              icon: const Icon(Icons.copy, size: 16),
              onPressed: () => Clipboard.setData(ClipboardData(text: message)),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Widget _diffText(String? value, bool changed) {
    return Text(
      value ?? '-',
      style: TextStyle(
        color: changed ? Colors.orange.shade800 : null,
        fontWeight: changed ? FontWeight.w700 : FontWeight.normal,
      ),
    );
  }

  Widget _status(String status) {
    final (label, color) = switch (status) {
      'changed' => ('变更', Colors.orange),
      'unchanged' => ('无变化', Colors.green),
      'skipped' => ('跳过', Colors.grey),
      'failed' => ('失败', Colors.red),
      _ => (status, Colors.blueGrey),
    };
    return _chip(label, color);
  }

  Widget _chip(String label, Color color) {
    return Chip(
      label: Text(label),
      side: BorderSide(color: color.withValues(alpha: 0.35)),
      backgroundColor: color.withValues(alpha: 0.08),
      labelStyle: TextStyle(color: color),
      visualDensity: VisualDensity.compact,
    );
  }

  String? _formatDate(DateTime? value) {
    if (value == null) return null;
    return _dateFmt.format(value.toLocal());
  }

  Future<void> _publish(List<RuntimeEnvCollectionResult> items) async {
    final service = context.read<EnvService>();
    try {
      final result = await service.publishCollected(items);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已发布 ${result.updated} 项变更')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('发布失败: $e')));
      }
    }
  }
}

class _EnvFormDialog extends StatefulWidget {
  final EnvInfo? env;
  const _EnvFormDialog({this.env});

  @override
  State<_EnvFormDialog> createState() => _EnvFormDialogState();
}

class _EnvFormDialogState extends State<_EnvFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _noCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _ywdbCtrl;
  late final TextEditingController _zjdbCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _versionCtrl;
  late final TextEditingController _seeurlCtrl;
  late final TextEditingController _webserverCtrl;
  late final TextEditingController _weblogCtrl;
  late final TextEditingController _memoCtrl;
  late final TextEditingController _dbtypeCtrl;

  bool get isEdit => widget.env != null;

  @override
  void initState() {
    super.initState();
    final e = widget.env;
    _noCtrl = TextEditingController(text: e?.eNo.toString() ?? '');
    _nameCtrl = TextEditingController(text: e?.eName ?? '');
    _ywdbCtrl = TextEditingController(text: e?.eYwdb ?? '');
    _zjdbCtrl = TextEditingController(text: e?.eZjdb ?? '');
    _urlCtrl = TextEditingController(text: e?.eUrl ?? '');
    _versionCtrl = TextEditingController(text: e?.eVersion ?? '');
    _seeurlCtrl = TextEditingController(text: e?.eSeeurl ?? '');
    _webserverCtrl = TextEditingController(text: e?.eWebserveraddr ?? '');
    _weblogCtrl = TextEditingController(text: e?.eWeblogpath ?? '');
    _memoCtrl = TextEditingController(text: e?.eMemo ?? '');
    _dbtypeCtrl = TextEditingController(text: e?.eDbtype ?? '');
  }

  @override
  void dispose() {
    _noCtrl.dispose();
    _nameCtrl.dispose();
    _ywdbCtrl.dispose();
    _zjdbCtrl.dispose();
    _urlCtrl.dispose();
    _versionCtrl.dispose();
    _seeurlCtrl.dispose();
    _webserverCtrl.dispose();
    _weblogCtrl.dispose();
    _memoCtrl.dispose();
    _dbtypeCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final env = EnvInfo(
      eNo: int.parse(_noCtrl.text),
      eName: _nameCtrl.text.isEmpty ? null : _nameCtrl.text,
      eYwdb: _ywdbCtrl.text.isEmpty ? null : _ywdbCtrl.text,
      eZjdb: _zjdbCtrl.text.isEmpty ? null : _zjdbCtrl.text,
      eUrl: _urlCtrl.text.isEmpty ? null : _urlCtrl.text,
      eVersion: _versionCtrl.text.isEmpty ? null : _versionCtrl.text,
      eSeeurl: _seeurlCtrl.text.isEmpty ? null : _seeurlCtrl.text,
      eWebserveraddr: _webserverCtrl.text.isEmpty ? null : _webserverCtrl.text,
      eWeblogpath: _weblogCtrl.text.isEmpty ? null : _weblogCtrl.text,
      eMemo: _memoCtrl.text.isEmpty ? null : _memoCtrl.text,
      eDbtype: _dbtypeCtrl.text.isEmpty ? null : _dbtypeCtrl.text,
    );
    Navigator.pop(context, env);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(isEdit ? '编辑环境' : '新增环境'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(
                  '编号 *',
                  _noCtrl,
                  enabled: !isEdit,
                  validator: (v) =>
                      (v == null || int.tryParse(v) == null) ? '请输入有效编号' : null,
                ),
                _field('环境别名', _nameCtrl),
                _field('业务库', _ywdbCtrl),
                _field('中间库', _zjdbCtrl),
                _field('访问地址', _urlCtrl),
                _field('版本号', _versionCtrl),
                _field('SEE平台地址', _seeurlCtrl),
                _field('Web服务地址', _webserverCtrl),
                _field('Web日志路径', _weblogCtrl),
                _field('备注', _memoCtrl),
                _field('数据库类型', _dbtypeCtrl),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    bool enabled = true,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        enabled: enabled,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}
