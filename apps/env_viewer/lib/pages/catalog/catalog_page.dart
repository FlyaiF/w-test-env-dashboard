import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../catalog/environment_store.dart';
import '../../catalog/environment_view.dart';
import '../../inventory/inventory_store.dart';
import '../../inventory/inventory_view.dart';
import 'catalog_editors.dart';
import 'catalog_link_editor.dart';
import 'component_access.dart';
import 'connection_sections.dart';

/// Browser + curation surface for the Environment Catalog. Lists Environments
/// from the backend, shows the selected Environment's Components, and drives
/// create/update/delete of both through the store (slice 03). Each Component
/// also offers Local Desktop Integration — launch the user's own SSH/DB tool
/// against its Server/Databases via brokered credentials (slice 06).
class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key});

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  int? _selectedId;

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
        _buildHeader(store, envs.length),
        if (store.error != null) _buildErrorBanner(store),
        if (store.loading) const LinearProgressIndicator(),
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
                    Expanded(child: _buildEnvList(envs, selected)),
                    const Divider(height: 1),
                    SizedBox(
                      height: 320,
                      child: _buildDetailPane(store, selected),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  SizedBox(width: 420, child: _buildEnvList(envs, selected)),
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

  Widget _buildHeader(EnvironmentStore store, int visibleCount) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final summary = Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('环境目录', style: theme.textTheme.headlineSmall),
              Text(
                '显示 $visibleCount / ${store.totalCount} 条',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          );
          final search = FilterHistoryTextField(
            controller: _searchController,
            filterText: _searchController.text,
            hintText: '搜索编号、名称、备注、组件、版本...',
            onChanged: (v) {
              setState(() {});
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 250), () {
                store.setSearch(v);
              });
            },
          );
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
          );

          if (constraints.maxWidth < 900) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: summary),
                    const SizedBox(width: 12),
                    actions,
                  ],
                ),
                const SizedBox(height: 8),
                search,
              ],
            );
          }

          return Row(
            children: [
              summary,
              const Spacer(),
              SizedBox(width: 340, child: search),
              const SizedBox(width: 8),
              actions,
            ],
          );
        },
      ),
    );
  }

  Widget _buildErrorBanner(EnvironmentStore store) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colorScheme.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              store.error!,
              style: TextStyle(color: colorScheme.error),
            ),
          ),
          TextButton(onPressed: store.load, child: const Text('重试')),
        ],
      ),
    );
  }

  Widget _buildEnvList(List<EnvironmentView> envs, EnvironmentView? selected) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      itemCount: envs.length,
      itemBuilder: (context, index) {
        final env = envs[index];
        return _EnvListTile(
          env: env,
          selected: selected?.id == env.id,
          onTap: () => setState(() => _selectedId = env.id),
        );
      },
    );
  }

  Widget _buildDetailPane(EnvironmentStore store, EnvironmentView? env) {
    if (env == null) {
      return Center(
        child: Text(
          '选择一个环境查看详情',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      );
    }
    return _EnvironmentDetail(
      env: env,
      collecting: store.isCollecting(env.id),
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
    final theme = Theme.of(context);
    final hasSearch = store.search.isNotEmpty;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasSearch ? Icons.search_off : Icons.dns_outlined,
            size: 56,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            hasSearch ? '没有匹配的环境' : '暂无环境',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

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
      ).showSnackBar(const SnackBar(content: Text('资源库存未就绪')));
      return;
    }
    if (!inventory.loaded) {
      await inventory.load();
      if (!mounted) return;
      if (!inventory.loaded) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(inventory.error ?? '资源库存加载失败')));
        return;
      }
    }
    if (!mounted) return;
    final store = context.read<EnvironmentStore>();
    final saved = await showComponentLinksEditor(
      context,
      component: component,
      servers: inventory.servers,
      databases: inventory.databases,
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

class _EnvListTile extends StatelessWidget {
  final EnvironmentView env;
  final bool selected;
  final VoidCallback onTap;

  const _EnvListTile({
    required this.env,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.35)
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '#${env.id}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      env.name,
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.widgets_outlined,
                    size: 15,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${env.componentCount} 个组件',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (env.memo != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        env.memo!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.outline,
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
    );
  }
}

class _EnvironmentDetail extends StatelessWidget {
  final EnvironmentView env;

  /// True while 立即采集 is in flight for this Environment; the button shows a
  /// spinner and refuses re-entry.
  final bool collecting;
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '#${env.id}',
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(env.name, style: theme.textTheme.headlineSmall),
                ),
                IconButton(
                  icon: collecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.radar),
                  tooltip: '立即采集',
                  onPressed: collecting ? null : onCollect,
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: '编辑环境',
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '删除环境',
                  onPressed: onDelete,
                ),
              ],
            ),
            if (env.memo != null) ...[
              const SizedBox(height: 10),
              SelectableText(env.memo!, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 20),
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
            const SizedBox(height: 10),
            if (env.components.isEmpty)
              Text(
                '该环境暂无组件',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              )
            else
              ...env.components.map(
                (c) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ComponentCard(
                    component: c,
                    environmentName: env.name,
                    onOpenUrl: onOpenUrl,
                    onEdit: () => onEditComponent(c),
                    onLink: () => onLinkComponent(c),
                    onDelete: () => onDeleteComponent(c),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ComponentCard extends StatelessWidget {
  static final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');

  final ComponentView component;
  final String environmentName;
  final Future<void> Function(String url) onOpenUrl;
  final VoidCallback onEdit;
  final VoidCallback onLink;
  final VoidCallback onDelete;

  const _ComponentCard({
    required this.component,
    required this.environmentName,
    required this.onOpenUrl,
    required this.onEdit,
    required this.onLink,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = component;
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.widgets_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                c.roleLabel,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _CollectionStatusChip(
                state: c.collectionState,
                label: c.collectionStatusLabel,
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: '编辑组件',
                visualDensity: VisualDensity.compact,
                onPressed: onEdit,
              ),
              IconButton(
                icon: const Icon(Icons.account_tree_outlined, size: 18),
                tooltip: '关联资源',
                visualDensity: VisualDensity.compact,
                onPressed: onLink,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: '删除组件',
                visualDensity: VisualDensity.compact,
                onPressed: onDelete,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _FieldGrid(
            fields: [
              _Field('版本', c.version),
              _Field(
                '版本更新时间',
                c.versionUpdatedAt == null
                    ? null
                    : _dateFmt.format(c.versionUpdatedAt!.toLocal()),
              ),
              _Field('版本探测', c.versionProbeLabel),
              _Field(
                '最近采集',
                c.lastCollectedAt == null
                    ? null
                    : _dateFmt.format(c.lastCollectedAt!.toLocal()),
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
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    c.url!,
                    maxLines: 1,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('打开'),
                  onPressed: () => onOpenUrl(c.url!),
                ),
              ],
            ),
          ],
          if (c.serverId != null || c.databaseIds.isNotEmpty) ...[
            const SizedBox(height: 12),
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
            const SizedBox(height: 12),
            ComponentAccessBar(
              serverId: c.serverId,
              databaseIds: c.databaseIds,
              databaseLabels: {
                for (final id in c.databaseIds)
                  if (dbRefs[id] != null) id: dbRefs[id]!.menuLabel,
              },
              connectionName: '$environmentName · ${c.roleLabel}',
            ),
          ],
        ],
      ),
    );
  }
}

class _CollectionStatusChip extends StatelessWidget {
  final CollectionState state;
  final String label;

  const _CollectionStatusChip({required this.state, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (state) {
      CollectionState.ok => (
        Colors.green.withValues(alpha: 0.15),
        Colors.green.shade800,
      ),
      CollectionState.failed => (scheme.errorContainer, scheme.error),
      CollectionState.unsupported => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      CollectionState.notCollected => (
        scheme.surfaceContainerHighest,
        scheme.outline,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
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
          runSpacing: 12,
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
    final theme = Theme.of(context);
    final value = field.value?.isNotEmpty == true ? field.value! : '-';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          field.label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(value, maxLines: 2, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
