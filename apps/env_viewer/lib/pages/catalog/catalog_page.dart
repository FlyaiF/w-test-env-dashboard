import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../catalog/environment_store.dart';
import '../../catalog/environment_view.dart';
import '../../config/config_store.dart';
import '../../inventory/inventory_store.dart';
import '../../inventory/inventory_view.dart';
import '../../remote_files/remote_file_store.dart';
import '../../services/access/access_launcher.dart';
import '../../services/remote_file/remote_file_session.dart';
import '../../services/ssh_tools/ssh_tool.dart';
import '../remote_files/open_remote_file.dart';
import 'catalog_editors.dart';
import 'catalog_link_editor.dart';
import 'component_access.dart';
import 'connection_sections.dart';

/// The ops glance-and-launch surface (设计方向 D): a scannable Environment
/// roster on the left (health dot, staleness flag, relative freshness), and on
/// the right the selected Environment's Components as compact, grid-aligned
/// rows — expandable per-row to full fields and brokered credentials. Machine
/// data renders in mono; row-end icon actions launch the user's SSH/DB tools.
class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key});

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  int? _selectedId;

  /// Component ids whose row is expanded to the full detail view.
  final Set<int> _expandedComponents = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EnvironmentStore>().load();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<EnvironmentStore>();
    final envs = store.environments;
    final selected = _selectedEnv(envs);

    return Column(
      children: [
        PageHeader(
          title: '环境目录',
          visibleCount: envs.length,
          totalCount: store.totalCount,
          search: FilterHistoryTextField(
            controller: _searchController,
            filterText: _searchController.text,
            hintText: '搜索编号、名称、备注、组件、版本...',
            onChanged: (v) {
              setState(() {});
              _debounce?.cancel();
              if (v.trim().isEmpty) {
                store.setSearch('');
                return;
              }
              _debounce = Timer(const Duration(milliseconds: 250), () {
                store.setSearch(v);
              });
            },
          ),
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新建环境'),
              onPressed: store.loading ? null : _createEnv,
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: store.loading ? null : store.load,
              tooltip: '刷新',
            ),
          ],
        ),
        if (store.error != null)
          ErrorBanner(message: store.error!, onRetry: store.load),
        // Reserved strip: the indicator appears without shifting the layout.
        SizedBox(
          height: 3,
          child: store.loading
              ? const LinearProgressIndicator(minHeight: 3)
              : null,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (envs.isEmpty && !store.loading) {
                return _buildEmptyState(store);
              }
              final compact = constraints.maxWidth < 900;
              if (compact) {
                return Column(
                  children: [
                    Expanded(child: _buildRoster(envs, selected)),
                    const Divider(height: 1),
                    SizedBox(
                      height: 320,
                      child: _buildDetailPane(store, selected),
                    ),
                  ],
                );
              }
              // Stretch, not the default center: the detail pane's scroll view
              // shrink-wraps its height, and centering a short Environment
              // floats it mid-pane.
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 380, child: _buildRoster(envs, selected)),
                  const VerticalDivider(width: 1),
                  Expanded(child: _buildDetailPane(store, selected)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRoster(List<EnvironmentView> envs, EnvironmentView? selected) {
    final tokens = AppTokens.of(context);
    return ColoredBox(
      color: tokens.rosterBg,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
        itemCount: envs.length,
        itemBuilder: (context, index) {
          final env = envs[index];
          return _RosterRow(
            env: env,
            selected: selected?.id == env.id,
            onTap: () => setState(() => _selectedId = env.id),
          );
        },
      ),
    );
  }

  Widget _buildDetailPane(EnvironmentStore store, EnvironmentView? env) {
    final tokens = AppTokens.of(context);
    if (env == null) {
      return Center(
        child: Text(
          '选择一个环境查看详情',
          style: TextStyle(color: tokens.textSecondary),
        ),
      );
    }
    return _EnvironmentDetail(
      env: env,
      collecting: store.isCollecting(env.id),
      expandedComponents: _expandedComponents,
      onToggleComponent: (id) => setState(() {
        if (!_expandedComponents.remove(id)) _expandedComponents.add(id);
      }),
      onCollect: () => _collectNow(env),
      onOpenUrl: _launchUrl,
      onEdit: () => _editEnv(env),
      onDelete: () => _deleteEnv(env),
      onAddComponent: () => _addComponent(env),
      onEditComponent: (c) => _editComponent(env, c),
      onLinkComponent: _linkComponent,
      onDeleteComponent: (c) => _deleteComponent(env, c),
    );
  }

  Widget _buildEmptyState(EnvironmentStore store) {
    final hasSearch = store.search.isNotEmpty;
    return EmptyState(
      icon: hasSearch ? Icons.search_off : Icons.dns_outlined,
      message: hasSearch ? '没有匹配的环境' : '暂无环境',
    );
  }

  /// Selection survives filtering: the chosen id sticks even while a filter
  /// hides it, and the first visible Environment stands in meanwhile.
  EnvironmentView? _selectedEnv(List<EnvironmentView> envs) {
    if (envs.isEmpty) return null;
    if (_selectedId != null) {
      for (final env in envs) {
        if (env.id == _selectedId) return env;
      }
    }
    return envs.first;
  }

  Future<void> _launchUrl(String url) async {
    var uri = Uri.tryParse(url);
    if (uri != null && !uri.hasScheme) {
      uri = Uri.parse('http://$url');
    }
    if (uri != null) {
      await launchUrl(uri);
    }
  }

  // ---- Collection (slice 05 / issue 08) ----------------------------------

  /// 立即采集: server-side Collection for one Environment, distinct from the
  /// toolbar 刷新 which only re-fetches what the backend already knows.
  Future<void> _collectNow(EnvironmentView env) async {
    final store = context.read<EnvironmentStore>();
    final error = await store.collectNow(env.id);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error ?? '环境「${env.name}」已采集')));
  }

  // ---- Curation (slice 03) ----------------------------------------------

  Future<void> _createEnv() async {
    final input = await showEnvironmentEditor(context);
    if (input == null || !mounted) return;
    final store = context.read<EnvironmentStore>();
    final ok = await store.createEnvironment(input);
    _report(store, ok, '环境已创建');
  }

  Future<void> _editEnv(EnvironmentView env) async {
    final input = await showEnvironmentEditor(context, existing: env);
    if (input == null || !mounted) return;
    final store = context.read<EnvironmentStore>();
    final ok = await store.updateEnvironment(env.id, input);
    _report(store, ok, '环境已更新');
  }

  Future<void> _deleteEnv(EnvironmentView env) async {
    final confirmed = await _confirm(
      '删除环境',
      '确定删除环境「${env.name}」及其组件？此操作不可撤销。',
    );
    if (!confirmed || !mounted) return;
    final store = context.read<EnvironmentStore>();
    final ok = await store.deleteEnvironment(env.id);
    if (!mounted) return;
    if (ok) setState(() => _selectedId = null);
    _report(store, ok, '环境已删除');
  }

  Future<void> _addComponent(EnvironmentView env) async {
    final input = await showComponentEditor(context);
    if (input == null || !mounted) return;
    final store = context.read<EnvironmentStore>();
    final ok = await store.addComponent(env.id, input);
    _report(store, ok, '组件已添加');
  }

  Future<void> _editComponent(
    EnvironmentView env,
    ComponentView component,
  ) async {
    final input = await showComponentEditor(context, existing: component);
    if (input == null || !mounted) return;
    final store = context.read<EnvironmentStore>();
    final ok = await store.updateComponent(env.id, component.id, input);
    _report(store, ok, '组件已更新');
  }

  Future<void> _deleteComponent(
    EnvironmentView env,
    ComponentView component,
  ) async {
    final confirmed = await _confirm('删除组件', '确定删除组件「${component.roleLabel}」？');
    if (!confirmed || !mounted) return;
    final store = context.read<EnvironmentStore>();
    final ok = await store.removeComponent(env.id, component.id);
    _report(store, ok, '组件已删除');
  }

  Future<void> _linkComponent(ComponentView component) async {
    final inventory = context.read<InventoryStore?>();
    if (inventory == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('资源清单未就绪')));
      return;
    }
    if (!inventory.loaded) {
      await inventory.load();
      if (!mounted) return;
      if (!inventory.loaded) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(inventory.error ?? '资源清单加载失败')));
        return;
      }
    }
    if (!mounted) return;
    final store = context.read<EnvironmentStore>();
    // Annotate each resource with the environments already referencing it, so
    // same-address entries in the picker are distinguishable.
    final serverUsage = <int, List<String>>{};
    final databaseUsage = <int, List<String>>{};
    void record(Map<int, List<String>> usage, int id, String name) {
      final names = usage.putIfAbsent(id, () => <String>[]);
      if (!names.contains(name)) names.add(name);
    }

    for (final env in store.allEnvironments) {
      for (final c in env.components) {
        if (c.serverId != null) record(serverUsage, c.serverId!, env.name);
        for (final databaseId in c.databaseIds) {
          record(databaseUsage, databaseId, env.name);
        }
      }
    }
    final saved = await showComponentLinksEditor(
      context,
      component: component,
      servers: inventory.servers,
      databases: inventory.databases,
      serverUsage: serverUsage,
      databaseUsage: databaseUsage,
      onSave: (input) async {
        final ok = await store.setComponentLinks(component.id, input);
        return ok ? null : (store.error ?? '操作失败');
      },
    );
    if (!saved || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('组件资源关联已更新')));
  }

  Future<bool> _confirm(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Surface the outcome of a store mutation. On success show a confirmation; on
  /// failure show the store's localized error (which it already captured).
  void _report(EnvironmentStore store, bool ok, String successMessage) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text(ok ? successMessage : (store.error ?? '操作失败'))),
    );
  }
}

/// Formats how long ago an instant was, for the roster's freshness column.
String relativeTimeLabel(DateTime? at, {DateTime? now}) {
  if (at == null) return '未采集';
  final delta = (now ?? DateTime.now()).difference(at);
  if (delta.inMinutes < 1) return '刚刚';
  if (delta.inMinutes < 60) return '${delta.inMinutes}分钟前';
  if (delta.inHours < 24) return '${delta.inHours}小时前';
  return '${delta.inDays}天前';
}

class _RosterRow extends StatelessWidget {
  final EnvironmentView env;
  final bool selected;
  final VoidCallback onTap;

  const _RosterRow({
    required this.env,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? tokens.selectionBg : Colors.transparent,
        borderRadius: BorderRadius.circular(AppTokens.radiusRow),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.radiusRow),
          hoverColor: tokens.hover,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: selected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTokens.radiusRow),
                    border: Border.all(color: tokens.selectionBorder),
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _HealthDot(state: env.health.state),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        env.name,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (env.health.isStale)
                      Tooltip(
                        message: '数据超过 24 小时未更新',
                        child: Icon(
                          Icons.warning_amber_rounded,
                          size: 15,
                          color: tokens.warn,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text(
                    '#${env.id} · ${env.componentCount}组件 · '
                    '${relativeTimeLabel(env.health.newestCollectedAt?.toLocal())}',
                    style: tokens.mono(
                      fontSize: 11.5,
                      color: tokens.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Health dot for a roster row: filled green OK, hollow neutral pending,
/// filled red failed. Shape + color双编码 so state reads without color alone.
class _HealthDot extends StatelessWidget {
  final EnvironmentHealthState state;

  const _HealthDot({required this.state});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return switch (state) {
      EnvironmentHealthState.ok => _dot(fill: tokens.ok),
      EnvironmentHealthState.pending => _dot(borderOnly: tokens.textSecondary),
      EnvironmentHealthState.failed => _dot(fill: tokens.err),
    };
  }

  Widget _dot({Color? fill, Color? borderOnly}) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: borderOnly == null
            ? null
            : Border.all(color: borderOnly, width: 1.4),
      ),
    );
  }
}

class _EnvironmentDetail extends StatelessWidget {
  final EnvironmentView env;

  /// True while 立即采集 is in flight for this Environment; the button shows a
  /// spinner and refuses re-entry.
  final bool collecting;
  final Set<int> expandedComponents;
  final ValueChanged<int> onToggleComponent;
  final VoidCallback onCollect;
  final Future<void> Function(String url) onOpenUrl;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAddComponent;
  final void Function(ComponentView component) onEditComponent;
  final void Function(ComponentView component) onLinkComponent;
  final void Function(ComponentView component) onDeleteComponent;

  const _EnvironmentDetail({
    required this.env,
    required this.collecting,
    required this.expandedComponents,
    required this.onToggleComponent,
    required this.onCollect,
    required this.onOpenUrl,
    required this.onEdit,
    required this.onDelete,
    required this.onAddComponent,
    required this.onEditComponent,
    required this.onLinkComponent,
    required this.onDeleteComponent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppTokens.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IdBadge(id: env.id),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(env.name, style: theme.textTheme.headlineSmall),
                ),
                Tooltip(
                  message: '立即采集',
                  child: FilledButton.tonalIcon(
                    icon: collecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.radar, size: 16),
                    label: const Text('采集'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: collecting ? null : onCollect,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  tooltip: '编辑环境',
                  visualDensity: VisualDensity.compact,
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  tooltip: '删除环境',
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                ),
              ],
            ),
            if (env.memo != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                env.memo!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ],
            if (env.seeUrl != null ||
                env.components.any((c) => c.url != null)) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (env.seeUrl != null)
                    _UrlChip(label: 'SEE', url: env.seeUrl!, onOpen: onOpenUrl),
                  for (final c in env.components)
                    if (c.url != null)
                      _UrlChip(
                        label: c.roleLabel,
                        url: c.url!,
                        onOpen: onOpenUrl,
                      ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Text(
                  '组件（${env.componentCount}）',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加组件'),
                  onPressed: onAddComponent,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (env.components.isEmpty)
              Text(
                '该环境暂无组件',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                ),
              )
            else ...[
              const _ComponentGridHeader(),
              const SizedBox(height: 4),
              ...env.components.map(
                (c) => _ComponentRow(
                  key: ValueKey(c.id),
                  component: c,
                  environmentName: env.name,
                  expanded: expandedComponents.contains(c.id),
                  onToggle: () => onToggleComponent(c.id),
                  onOpenUrl: onOpenUrl,
                  onEdit: () => onEditComponent(c),
                  onLink: () => onLinkComponent(c),
                  onDelete: () => onDeleteComponent(c),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Copy a URL for sharing — the raw stored string, no normalization.
Future<void> _copyUrl(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  await Clipboard.setData(ClipboardData(text: url));
  messenger.showSnackBar(const SnackBar(content: Text('已复制链接')));
}

/// One elevated link action in the environment header: the labeled button opens
/// the URL in the browser (full URL in the tooltip), the icon beside it copies
/// the raw value for sharing.
class _UrlChip extends StatelessWidget {
  final String label;
  final String url;
  final Future<void> Function(String url) onOpen;

  const _UrlChip({
    required this.label,
    required this.url,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: url,
          child: TextButton.icon(
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(label),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: () => onOpen(url),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy_outlined, size: 14),
          tooltip: '复制链接',
          visualDensity: VisualDensity.compact,
          onPressed: () => _copyUrl(context, url),
        ),
      ],
    );
  }
}

/// Fixed column plan for the component grid; shared by the header and every
/// row so the mono data stays vertically aligned.
abstract final class _Cols {
  static const double dot = 18;
  static const double role = 92;
  static const double version = 134;
  static const double updated = 128;
  static const double chip = 72;
  static const double actions = 88;
  static const double chevron = 22;
  static const double gap = 8;
}

class _ComponentGridHeader extends StatelessWidget {
  const _ComponentGridHeader();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: tokens.textSecondary,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tokens.tableHeaderBg,
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
      ),
      child: Row(
        children: [
          const SizedBox(width: _Cols.dot),
          SizedBox(
            width: _Cols.role,
            child: Text('角色', style: style),
          ),
          const SizedBox(width: _Cols.gap),
          SizedBox(
            width: _Cols.version,
            child: Text('版本', style: style),
          ),
          const SizedBox(width: _Cols.gap),
          SizedBox(
            width: _Cols.updated,
            child: Text('版本更新', style: style),
          ),
          const SizedBox(width: _Cols.gap),
          Expanded(child: Text('主机', style: style)),
          SizedBox(
            width: _Cols.chip,
            child: Text('状态', style: style),
          ),
          const SizedBox(width: _Cols.actions + _Cols.chevron),
        ],
      ),
    );
  }
}

class _ComponentRow extends StatefulWidget {
  final ComponentView component;
  final String environmentName;
  final bool expanded;
  final VoidCallback onToggle;
  final Future<void> Function(String url) onOpenUrl;
  final VoidCallback onEdit;
  final VoidCallback onLink;
  final VoidCallback onDelete;

  const _ComponentRow({
    super.key,
    required this.component,
    required this.environmentName,
    required this.expanded,
    required this.onToggle,
    required this.onOpenUrl,
    required this.onEdit,
    required this.onLink,
    required this.onDelete,
  });

  @override
  State<_ComponentRow> createState() => _ComponentRowState();
}

class _ComponentRowState extends State<_ComponentRow> {
  static final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');
  static final _shortFmt = DateFormat('MM-dd HH:mm');

  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final c = widget.component;
    // Resolve Server/Database references to friendly labels (ADR-0006); falls
    // back to `#id` when inventory is unavailable.
    final inventory = context.watch<InventoryStore?>();
    final serversById = inventory?.serversById ?? const <int, ServerView>{};
    final databasesById =
        inventory?.databasesById ?? const <int, DatabaseView>{};
    final server = c.serverId == null ? null : serversById[c.serverId];
    final dbRefs = {
      for (final id in c.databaseIds)
        if (databasesById[id] != null) id: databasesById[id]!,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: tokens.cardBg,
        borderRadius: BorderRadius.circular(AppTokens.radiusRow),
        border: Border.all(color: tokens.cardBorder),
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: widget.onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: _Cols.dot,
                      child: _CollectionDot(state: c.collectionState),
                    ),
                    SizedBox(
                      width: _Cols.role,
                      child: Text(
                        c.roleLabel,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: _Cols.gap),
                    SizedBox(
                      width: _Cols.version,
                      child: Text(
                        c.version ?? '-',
                        style: tokens.mono(fontSize: 12.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: _Cols.gap),
                    SizedBox(
                      width: _Cols.updated,
                      child: Text(
                        c.versionUpdatedAt == null
                            ? '-'
                            : _shortFmt.format(c.versionUpdatedAt!.toLocal()),
                        style: tokens.mono(
                          fontSize: 12.5,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: _Cols.gap),
                    Expanded(
                      child: Text(
                        c.serverId == null
                            ? '-'
                            : (server?.displayLabel ?? '#${c.serverId}'),
                        style: tokens.mono(fontSize: 12.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(
                      width: _Cols.chip,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: StatusChip(
                          kind: switch (c.collectionState) {
                            CollectionState.ok => StatusChipKind.ok,
                            CollectionState.failed => StatusChipKind.err,
                            CollectionState.unsupported => StatusChipKind.na,
                            CollectionState.notCollected => StatusChipKind.none,
                          },
                          label: c.collectionStatusLabel,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: _Cols.actions,
                      child: AnimatedOpacity(
                        opacity: _hovered || widget.expanded ? 1.0 : 0.6,
                        duration: const Duration(milliseconds: 120),
                        child: _RowLaunchActions(
                          component: c,
                          environmentName: widget.environmentName,
                          databaseLabels: {
                            for (final id in c.databaseIds)
                              if (dbRefs[id] != null) id: dbRefs[id]!.menuLabel,
                          },
                          databaseTypes: {
                            for (final id in c.databaseIds)
                              if (dbRefs[id] != null) id: dbRefs[id]!.type,
                          },
                        ),
                      ),
                    ),
                    SizedBox(
                      width: _Cols.chevron,
                      child: Icon(
                        widget.expanded ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.expanded)
              _ComponentExpandedBody(
                component: c,
                server: server,
                dbRefs: dbRefs,
                dateFmt: _dateFmt,
                onOpenUrl: widget.onOpenUrl,
                onEdit: widget.onEdit,
                onLink: widget.onLink,
                onDelete: widget.onDelete,
              ),
          ],
        ),
      ),
    );
  }
}

/// Collection dot for a component row, mirroring the roster's health language.
class _CollectionDot extends StatelessWidget {
  final CollectionState state;

  const _CollectionDot({required this.state});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final (Color? fill, Color? border) = switch (state) {
      CollectionState.ok => (tokens.ok, null),
      CollectionState.failed => (tokens.err, null),
      CollectionState.unsupported => (tokens.neutralChipBg, tokens.border),
      CollectionState.notCollected => (null, tokens.textSecondary),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: border == null ? null : Border.all(color: border, width: 1.4),
        ),
      ),
    );
  }
}

/// Row-end fixed icon action column: `>_` SSH 连接 and `⛁` 数据库工具 as uniform
/// icon buttons; an invisible placeholder keeps column alignment when a
/// Component lacks the resource.
class _RowLaunchActions extends StatelessWidget {
  final ComponentView component;
  final String environmentName;
  final Map<int, String> databaseLabels;
  final Map<int, String?> databaseTypes;

  const _RowLaunchActions({
    required this.component,
    required this.environmentName,
    required this.databaseLabels,
    required this.databaseTypes,
  });

  @override
  Widget build(BuildContext context) {
    final launcher = context.read<AccessLauncher?>();
    final config = context.watch<ConfigStore?>();
    final serverId = component.serverId;
    final databaseIds = component.databaseIds;

    final sshOptions = (launcher != null && serverId != null)
        ? sshLaunchOptions(
            launcher,
            serverId,
            preferredMode: config?.passwordMode ?? PasswordMode.argv,
            executablePaths: config?.sshExecutablePaths,
            preferredToolId: config?.defaultTerminalToolId,
          )
        : const <LaunchOption>[];
    final dbOptions = (launcher != null && databaseIds.isNotEmpty)
        ? dbLaunchOptions(
            launcher,
            databaseIds,
            connectionName: '$environmentName · ${component.roleLabel}',
            databaseLabels: databaseLabels,
            databaseTypes: databaseTypes,
            executablePaths: config?.dbExecutablePaths,
          )
        : const <LaunchOption>[];

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _LogLaunchSlot(
          component: component,
          environmentName: environmentName,
        ),
        const SizedBox(width: 2),
        _LaunchIconSlot(
          present: serverId != null,
          icon: Icons.terminal,
          tooltip: 'SSH 连接',
          emptyTooltip: '当前平台没有可用的 SSH 工具',
          options: sshOptions,
        ),
        const SizedBox(width: 2),
        _LaunchIconSlot(
          present: databaseIds.isNotEmpty,
          icon: Icons.storage,
          tooltip: '数据库工具',
          emptyTooltip: '当前平台没有可用的数据库工具',
          options: dbOptions,
        ),
      ],
    );
  }
}

/// The 查看日志 slot: one click brokers credentials, opens the component's
/// 日志位置 in follow mode, and jumps to the 日志文件 page. Disabled with an
/// explanatory tooltip when the component lacks a linked Server or a 日志位置.
class _LogLaunchSlot extends StatelessWidget {
  final ComponentView component;
  final String environmentName;

  const _LogLaunchSlot({
    required this.component,
    required this.environmentName,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final store = context.read<RemoteFileStore?>();
    final serverId = component.serverId;
    final logLocation = component.logLocation;
    final ready = store != null &&
        serverId != null &&
        logLocation != null &&
        logLocation.isNotEmpty;

    if (!ready) {
      return Tooltip(
        message: serverId == null ? '未关联运行主机' : '未配置日志位置',
        child: SizedBox(
          width: _LaunchIconSlot.size,
          height: _LaunchIconSlot.size,
          child: Icon(Icons.article_outlined, size: 16, color: tokens.border),
        ),
      );
    }

    return SizedBox(
      width: _LaunchIconSlot.size,
      height: _LaunchIconSlot.size,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 16,
        icon: const Icon(Icons.article_outlined),
        color: tokens.accent,
        tooltip: '查看日志',
        onPressed: () => openRemoteFile(
          context,
          store: store,
          serverId: serverId,
          title: '$environmentName · ${component.roleLabel}',
          path: logLocation,
          mode: RemoteFileMode.follow,
          jumpToPage: true,
        ),
      ),
    );
  }
}

/// One uniform-size launch slot. Absent resource → invisible placeholder of
/// identical size (column alignment); zero installed tools → disabled with an
/// explanatory tooltip; one option → direct launch; many → popup menu.
class _LaunchIconSlot extends StatefulWidget {
  static const double size = 26;

  final bool present;
  final IconData icon;
  final String tooltip;
  final String emptyTooltip;
  final List<LaunchOption> options;

  const _LaunchIconSlot({
    required this.present,
    required this.icon,
    required this.tooltip,
    required this.emptyTooltip,
    required this.options,
  });

  @override
  State<_LaunchIconSlot> createState() => _LaunchIconSlotState();
}

class _LaunchIconSlotState extends State<_LaunchIconSlot> {
  bool _busy = false;

  Future<void> _run(LaunchOption option) async {
    if (_busy) return;
    setState(() => _busy = true);
    LaunchResult result;
    try {
      result = await option.run();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message ?? (result.ok ? '已启动' : '启动失败'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    if (!widget.present) {
      return const SizedBox(
        width: _LaunchIconSlot.size,
        height: _LaunchIconSlot.size,
      );
    }

    final iconWidget = _busy
        ? const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(widget.icon, size: 16);

    if (widget.options.isEmpty) {
      return Tooltip(
        message: widget.emptyTooltip,
        child: SizedBox(
          width: _LaunchIconSlot.size,
          height: _LaunchIconSlot.size,
          child: Icon(widget.icon, size: 16, color: tokens.border),
        ),
      );
    }

    if (widget.options.length == 1) {
      return SizedBox(
        width: _LaunchIconSlot.size,
        height: _LaunchIconSlot.size,
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 16,
          icon: iconWidget,
          color: tokens.accent,
          tooltip: widget.tooltip,
          onPressed: _busy ? null : () => _run(widget.options.first),
        ),
      );
    }

    return SizedBox(
      width: _LaunchIconSlot.size,
      height: _LaunchIconSlot.size,
      child: PopupMenuButton<int>(
        enabled: !_busy,
        tooltip: widget.tooltip,
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        onSelected: (i) => _run(widget.options[i]),
        itemBuilder: (context) => launchMenuEntries(context, widget.options),
        child: Center(
          child: IconTheme(
            data: IconThemeData(color: tokens.accent),
            child: iconWidget,
          ),
        ),
      ),
    );
  }
}

class _ComponentExpandedBody extends StatelessWidget {
  final ComponentView component;
  final ServerView? server;
  final Map<int, DatabaseView> dbRefs;
  final DateFormat dateFmt;
  final Future<void> Function(String url) onOpenUrl;
  final VoidCallback onEdit;
  final VoidCallback onLink;
  final VoidCallback onDelete;

  const _ComponentExpandedBody({
    required this.component,
    required this.server,
    required this.dbRefs,
    required this.dateFmt,
    required this.onOpenUrl,
    required this.onEdit,
    required this.onLink,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppTokens.of(context);
    final c = component;
    return Container(
      decoration: BoxDecoration(
        color: tokens.cardBodyBg,
        border: Border(top: BorderSide(color: tokens.borderSoft)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '详细信息',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 16),
                tooltip: '编辑组件',
                visualDensity: VisualDensity.compact,
                onPressed: onEdit,
              ),
              IconButton(
                icon: const Icon(Icons.account_tree_outlined, size: 16),
                tooltip: '关联资源',
                visualDensity: VisualDensity.compact,
                onPressed: onLink,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                tooltip: '删除组件',
                visualDensity: VisualDensity.compact,
                onPressed: onDelete,
              ),
            ],
          ),
          if (c.collectionState == CollectionState.failed &&
              c.collectionDetail != null) ...[
            const SizedBox(height: 2),
            SelectableText(
              '采集失败：${c.collectionDetail}',
              style: TextStyle(fontSize: 12, color: tokens.err),
            ),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 4),
          _FieldGrid(
            fields: [
              _Field('版本', c.version),
              _Field(
                '版本更新时间',
                c.versionUpdatedAt == null
                    ? null
                    : dateFmt.format(c.versionUpdatedAt!.toLocal()),
              ),
              _Field('版本探测', c.versionProbeLabel),
              _Field(
                '最近采集',
                c.lastCollectedAt == null
                    ? null
                    : dateFmt.format(c.lastCollectedAt!.toLocal()),
              ),
              _Field('协议', c.protocol),
              _Field('监听端口', c.listenPort?.toString()),
              _Field('日志位置', c.logLocation),
              _Field(
                '运行主机',
                c.serverId == null
                    ? null
                    : (server?.displayLabel ?? '#${c.serverId}'),
              ),
            ],
          ),
          if (c.url != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    c.url!,
                    maxLines: 1,
                    style: tokens.mono(fontSize: 12.5),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('打开'),
                  onPressed: () => onOpenUrl(c.url!),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_outlined, size: 14),
                  tooltip: '复制链接',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _copyUrl(context, c.url!),
                ),
              ],
            ),
          ],
          if (c.serverId != null || c.databaseIds.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            if (c.serverId != null)
              SshInfoSection(
                key: ValueKey(c.serverId),
                serverId: c.serverId!,
                server: server,
              ),
            if (c.serverId != null && c.databaseIds.isNotEmpty)
              const SizedBox(height: 12),
            if (c.databaseIds.isNotEmpty)
              DatabaseInfoSection(
                databaseIds: c.databaseIds,
                databaseRefs: dbRefs,
              ),
          ],
        ],
      ),
    );
  }
}

class _Field {
  final String label;
  final String? value;

  const _Field(this.label, this.value);
}

class _FieldGrid extends StatelessWidget {
  final List<_Field> fields;

  const _FieldGrid({required this.fields});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 520;
        return Wrap(
          spacing: 12,
          runSpacing: 10,
          children: fields
              .map(
                (f) => SizedBox(
                  width: twoColumns
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth,
                  child: _FieldView(field: f),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _FieldView extends StatelessWidget {
  final _Field field;

  const _FieldView({required this.field});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final value = field.value?.isNotEmpty == true ? field.value! : '-';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          field.label,
          style: TextStyle(fontSize: 11, color: tokens.textSecondary),
        ),
        const SizedBox(height: 2),
        SelectableText(value, maxLines: 2, style: tokens.mono()),
      ],
    );
  }
}
