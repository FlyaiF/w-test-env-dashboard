import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/env_info.dart';
import '../../models/runtime_env_collection.dart';
import '../../services/env_service.dart';
import 'package:shared_ui/shared_ui.dart';

enum _ManagementFilter { incomplete, logReady, recent }

class ManagementPage extends StatefulWidget {
  const ManagementPage({super.key});

  @override
  State<ManagementPage> createState() => _ManagementPageState();
}

class _ManagementPageState extends State<ManagementPage> {
  final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');
  final _searchController = TextEditingController();
  final _tableScrollController = ScrollController();
  final Set<_ManagementFilter> _filters = {};
  Timer? _debounce;
  int? _selectedEnvNo;
  int? _lastVisibleEnvCount;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _tableScrollController.dispose();
    super.dispose();
  }

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
    final envs = _applyFilters(service.filteredEnvs);
    final selected = _selectedEnv(envs);
    if (_lastVisibleEnvCount != envs.length) {
      _lastVisibleEnvCount = envs.length;
      _resetTableScroll();
    }

    return Column(
      children: [
        _buildHeader(service, envs.length),
        if (service.loading ||
            service.syncing ||
            service.collecting ||
            service.publishingCollected)
          const LinearProgressIndicator(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 1020;
              if (envs.isEmpty && !service.loading) {
                return _emptyState();
              }
              if (compact) {
                return Column(
                  children: [
                    Expanded(child: _buildTable(envs, selected)),
                    const Divider(height: 1),
                    SizedBox(height: 300, child: _buildDetailPane(selected)),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(flex: 4, child: _buildTable(envs, selected)),
                  const VerticalDivider(width: 1),
                  Expanded(flex: 3, child: _buildDetailPane(selected)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(EnvService service, int visibleCount) {
    final theme = Theme.of(context);
    final totalCount = service.allEnvs.isNotEmpty
        ? service.allEnvs.length
        : service.total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('环境管理', style: theme.textTheme.headlineSmall),
              const SizedBox(width: 12),
              Text(
                '显示 $visibleCount / $totalCount 条',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 320,
                child: FilterHistoryTextField(
                  controller: _searchController,
                  filterText: _searchController.text,
                  hintText: '搜索编号、名称、地址、日志、版本...',
                  onChanged: (value) {
                    setState(() {});
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), () {
                      service.setSearch(value);
                      _resetTableScroll();
                    });
                  },
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: service.collecting ? null : _collectRuntimeInfo,
                icon: const Icon(Icons.compare_arrows),
                label: const Text('采集运行库信息'),
              ),
              FilledButton.icon(
                onPressed: () => _showForm(),
                icon: const Icon(Icons.add),
                label: const Text('新增环境'),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: service.syncing ? null : service.sync,
                tooltip: '从远程刷新',
              ),
              _filterChip(_ManagementFilter.incomplete, '缺少配置', Icons.warning),
              _filterChip(_ManagementFilter.logReady, '可看日志', Icons.article),
              _filterChip(_ManagementFilter.recent, '30天内更新', Icons.schedule),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChip(_ManagementFilter filter, String label, IconData icon) {
    final selected = _filters.contains(filter);
    return FilterChip(
      selected: selected,
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onSelected: (value) {
        setState(() {
          if (value) {
            _filters.add(filter);
          } else {
            _filters.remove(filter);
          }
        });
        _resetTableScroll();
      },
    );
  }

  Widget _buildTable(List<EnvInfo> envs, EnvInfo? selected) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: const [
              _TableHeaderCell(width: 72, label: '编号'),
              _TableHeaderCell(flex: 2, label: '环境别名'),
              _TableHeaderCell(flex: 4, label: '访问地址'),
              _TableHeaderCell(flex: 3, label: '版本号'),
              _TableHeaderCell(width: 150, label: '更新时间'),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _tableScrollController,
            itemCount: envs.length,
            itemBuilder: (context, index) {
              final env = envs[index];
              final isSelected = selected?.eNo == env.eNo;
              return _TableRow(
                env: env,
                dateFmt: _dateFmt,
                selected: isSelected,
                onTap: () => setState(() => _selectedEnvNo = env.eNo),
              );
            },
          ),
        ),
      ],
    );
  }

  void _resetTableScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tableScrollController.hasClients) {
        _tableScrollController.jumpTo(0);
      }
    });
  }

  Widget _buildDetailPane(EnvInfo? env) {
    final theme = Theme.of(context);
    if (env == null) {
      return Center(
        child: Text(
          '选择一个环境查看完整配置',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  env.eName ?? '环境 #${env.eNo}',
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '编号 ${env.eNo}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => _showForm(env: env),
                icon: const Icon(Icons.edit),
                label: const Text('编辑环境'),
              ),
              OutlinedButton.icon(
                onPressed: () => _deleteEnv(env),
                icon: Icon(Icons.delete, color: theme.colorScheme.error),
                label: Text(
                  '删除',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statusPill('访问地址', Icons.link, env.eUrl != null),
              _statusPill('日志', Icons.article_outlined, _hasLog(env)),
              _statusPill(
                '数据库',
                Icons.storage_outlined,
                env.eYwdb != null || env.eZjdb != null,
              ),
              _statusPill('版本', Icons.label_outline, env.eVersion != null),
            ],
          ),
          const SizedBox(height: 16),
          _detailSection('运行信息', [
            _DetailRow('访问地址', env.eUrl),
            _DetailRow('SEE平台', env.eSeeurl),
            _DetailRow('版本号', env.eVersion),
            _DetailRow(
              '更新时间',
              env.eUpdatetime == null
                  ? null
                  : _dateFmt.format(env.eUpdatetime!.toLocal()),
            ),
          ]),
          _detailSection('数据库', [
            _DetailRow('业务库', env.eYwdb),
            _DetailRow('中间库', env.eZjdb),
            _DetailRow('数据库类型', env.eDbtype),
          ]),
          _detailSection('日志', [
            _DetailRow('Web服务地址', env.eWebserveraddr),
            _DetailRow('Web日志路径', env.eWeblogpath),
          ]),
          _detailSection('备注', [_DetailRow('备注', env.eMemo)]),
        ],
      ),
    );
  }

  Widget _statusPill(String label, IconData icon, bool ok) {
    final color = ok
        ? Colors.green.shade700
        : Theme.of(context).colorScheme.error;
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(ok ? '$label已配置' : '$label缺失'),
      side: BorderSide(color: color.withValues(alpha: 0.35)),
      backgroundColor: color.withValues(alpha: 0.08),
      labelStyle: TextStyle(color: color),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _detailSection(String title, List<_DetailRow> rows) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final row in rows) _detailRow(row),
        ],
      ),
    );
  }

  Widget _detailRow(_DetailRow row) {
    final value = row.value?.isNotEmpty == true ? row.value! : '-';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              row.label,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          Expanded(child: SelectableText(value)),
          if (row.value?.isNotEmpty == true)
            IconButton(
              tooltip: '复制${row.label}',
              icon: const Icon(Icons.copy, size: 16),
              visualDensity: VisualDensity.compact,
              onPressed: () => _copyToClipboard(row.value!, row.label),
            ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        '没有匹配的环境',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }

  List<EnvInfo> _applyFilters(List<EnvInfo> envs) {
    var result = envs;
    for (final filter in _filters) {
      result = result.where((env) {
        switch (filter) {
          case _ManagementFilter.incomplete:
            return env.eUrl == null ||
                env.eVersion == null ||
                env.eWebserveraddr == null ||
                env.eWeblogpath == null;
          case _ManagementFilter.logReady:
            return _hasLog(env);
          case _ManagementFilter.recent:
            final updated = env.eUpdatetime;
            if (updated == null) return false;
            return updated.toLocal().isAfter(
              DateTime.now().subtract(const Duration(days: 30)),
            );
        }
      }).toList();
    }
    return result;
  }

  EnvInfo? _selectedEnv(List<EnvInfo> envs) {
    if (envs.isEmpty) return null;
    if (_selectedEnvNo != null) {
      for (final env in envs) {
        if (env.eNo == _selectedEnvNo) return env;
      }
    }
    return envs.first;
  }

  bool _hasLog(EnvInfo env) =>
      env.eWebserveraddr != null && env.eWeblogpath != null;

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制$label'),
        duration: const Duration(seconds: 1),
      ),
    );
  }
}

class _DetailRow {
  final String label;
  final String? value;

  const _DetailRow(this.label, this.value);
}

class _TableHeaderCell extends StatelessWidget {
  final double? width;
  final int? flex;
  final String label;

  const _TableHeaderCell({this.width, this.flex, required this.label});

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      overflow: TextOverflow.ellipsis,
    );
    if (width != null) {
      return SizedBox(width: width, child: text);
    }
    return Expanded(flex: flex ?? 1, child: text);
  }
}

class _TableRow extends StatelessWidget {
  final EnvInfo env;
  final DateFormat dateFmt;
  final bool selected;
  final VoidCallback onTap;

  const _TableRow({
    required this.env,
    required this.dateFmt,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final updated = env.eUpdatetime == null
        ? '-'
        : dateFmt.format(env.eUpdatetime!.toLocal());
    return Material(
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.28)
          : colorScheme.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              _TableCell(width: 72, child: Text('${env.eNo}')),
              _TableCell(flex: 2, child: Text(env.eName ?? '-')),
              _TableCell(flex: 4, child: Text(env.eUrl ?? '-')),
              _TableCell(flex: 3, child: Text(env.eVersion ?? '-')),
              _TableCell(width: 150, child: Text(updated)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TableCell extends StatelessWidget {
  final double? width;
  final int? flex;
  final Widget child;

  const _TableCell({this.width, this.flex, required this.child});

  @override
  Widget build(BuildContext context) {
    final content = DefaultTextStyle.merge(
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      child: child,
    );
    if (width != null) {
      return SizedBox(width: width, child: content);
    }
    return Expanded(flex: flex ?? 1, child: content);
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
