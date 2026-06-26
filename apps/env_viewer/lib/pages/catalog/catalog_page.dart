import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../catalog/environment_store.dart';
import '../../catalog/environment_view.dart';

/// Read-only browser for the Environment Catalog. Lists Environments from the
/// backend and shows the selected Environment's Components. No editing, no
/// launching — curation lands in slice 03 and tool launching in slice 06.
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
                    SizedBox(height: 320, child: _buildDetailPane(selected)),
                  ],
                );
              }
              return Row(
                children: [
                  SizedBox(width: 420, child: _buildEnvList(envs, selected)),
                  const VerticalDivider(width: 1),
                  Expanded(child: _buildDetailPane(selected)),
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
      child: Row(
        children: [
          Text('环境目录', style: theme.textTheme.headlineSmall),
          const SizedBox(width: 12),
          Text(
            '显示 $visibleCount / ${store.totalCount} 条',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 340,
            child: FilterHistoryTextField(
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
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: store.loading ? null : store.load,
            tooltip: '刷新',
          ),
        ],
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

  Widget _buildDetailPane(EnvironmentView? env) {
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
    return _EnvironmentDetail(env: env, onOpenUrl: _launchUrl);
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
  final Future<void> Function(String url) onOpenUrl;

  const _EnvironmentDetail({required this.env, required this.onOpenUrl});

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
              ],
            ),
            if (env.memo != null) ...[
              const SizedBox(height: 10),
              SelectableText(env.memo!, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 20),
            Text(
              '组件（${env.componentCount}）',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
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
                  child: _ComponentCard(component: c, onOpenUrl: onOpenUrl),
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
  final Future<void> Function(String url) onOpenUrl;

  const _ComponentCard({required this.component, required this.onOpenUrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = component;
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
              Icon(Icons.widgets_outlined, size: 18, color: theme.colorScheme.primary),
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
            ],
          ),
          const SizedBox(height: 12),
          _FieldGrid(
            fields: [
              _Field('版本', c.version),
              _Field(
                '部署时间',
                c.deployTime == null
                    ? null
                    : _dateFmt.format(c.deployTime!.toLocal()),
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
                c.serverId == null ? null : '#${c.serverId}',
              ),
              _Field(
                '使用数据库',
                c.databaseIds.isEmpty
                    ? null
                    : c.databaseIds.map((id) => '#$id').join('、'),
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
        SelectableText(
          value,
          maxLines: 2,
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}
