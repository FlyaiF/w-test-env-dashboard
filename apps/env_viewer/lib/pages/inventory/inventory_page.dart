import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../catalog/environment_view.dart';
import '../../inventory/inventory_store.dart';
import '../../inventory/inventory_view.dart';
import 'inventory_editors.dart';

/// Standalone presentation for the shared Server/Database Resource Inventory.
/// Routing is intentionally owned by the application shell, not this page.
class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchController = TextEditingController();
  int _activeTab = 0;
  String _query = '';

  bool get _showingServers => _activeTab == 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(_handleTabChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<InventoryStore>().load();
    });
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_handleTabChange)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_activeTab == _tabController.index) return;
    setState(() {
      _activeTab = _tabController.index;
      _query = '';
      _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<InventoryStore>();
    final servers = _filteredServers(store.servers);
    final databases = _filteredDatabases(store.databases);
    final visibleCount = _showingServers ? servers.length : databases.length;
    final totalCount = _showingServers
        ? store.servers.length
        : store.databases.length;

    return Column(
      children: [
        _buildHeader(store, visibleCount, totalCount),
        if (store.error != null)
          _InventoryErrorBanner(message: store.error!, onRetry: store.load),
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '服务器'),
            Tab(text: '数据库'),
          ],
        ),
        if (store.loading && store.loaded) const LinearProgressIndicator(),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildServerBody(store, servers),
              _buildDatabaseBody(store, databases),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(InventoryStore store, int visibleCount, int totalCount) {
    final theme = Theme.of(context);
    final summary = Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('资源清单', style: theme.textTheme.headlineSmall),
        Text(
          '显示 $visibleCount / $totalCount 条',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
    final search = TextField(
      key: const ValueKey('inventory-search-field'),
      controller: _searchController,
      decoration: InputDecoration(
        hintText: _showingServers ? '搜索主机、系统、SSH...' : '搜索用途、类型、地址、用户名...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: '清除搜索',
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
                icon: const Icon(Icons.clear),
              ),
        isDense: true,
      ),
      onChanged: (value) => setState(() => _query = value.trim()),
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          key: const ValueKey('inventory-create-button'),
          onPressed: store.loading ? null : _createCurrent,
          icon: const Icon(Icons.add, size: 18),
          label: Text(_showingServers ? '新建服务器' : '新建数据库'),
        ),
        const SizedBox(width: 8),
        IconButton(
          key: const ValueKey('inventory-refresh-button'),
          onPressed: store.loading ? null : store.load,
          icon: const Icon(Icons.refresh),
          tooltip: '刷新资源清单',
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
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
              SizedBox(width: 360, child: search),
              const SizedBox(width: 8),
              actions,
            ],
          );
        },
      ),
    );
  }

  Widget _buildServerBody(InventoryStore store, List<ServerView> servers) {
    if (store.loading && !store.loaded) {
      return const Center(
        child: CircularProgressIndicator(
          key: ValueKey('inventory-initial-loading'),
        ),
      );
    }
    if (servers.isEmpty) {
      return _EmptyInventory(
        icon: _query.isEmpty ? Icons.dns_outlined : Icons.search_off,
        message: _query.isEmpty ? '暂无服务器' : '没有匹配的服务器',
      );
    }
    return _InventoryGrid(
      itemCount: servers.length,
      itemBuilder: (context, index) {
        final server = servers[index];
        return _ServerCard(
          server: server,
          onUsage: () => _showServerUsage(server),
          onEdit: () => _editServer(server),
          onDelete: () => _deleteServer(server),
        );
      },
    );
  }

  Widget _buildDatabaseBody(
    InventoryStore store,
    List<DatabaseView> databases,
  ) {
    if (store.loading && !store.loaded) {
      return const Center(
        child: CircularProgressIndicator(
          key: ValueKey('inventory-initial-loading-databases'),
        ),
      );
    }
    if (databases.isEmpty) {
      return _EmptyInventory(
        icon: _query.isEmpty ? Icons.storage_outlined : Icons.search_off,
        message: _query.isEmpty ? '暂无数据库' : '没有匹配的数据库',
      );
    }
    return _InventoryGrid(
      itemCount: databases.length,
      itemBuilder: (context, index) {
        final database = databases[index];
        return _DatabaseCard(
          database: database,
          onUsage: () => _showDatabaseUsage(database),
          onEdit: () => _editDatabase(database),
          onDelete: () => _deleteDatabase(database),
        );
      },
    );
  }

  List<ServerView> _filteredServers(List<ServerView> servers) {
    final query = _query.toLowerCase();
    if (query.isEmpty) return servers;
    return servers
        .where((server) {
          return [
            server.id.toString(),
            server.host,
            server.os,
            server.osLabel,
            server.sshAddress,
          ].whereType<String>().any(
            (value) => value.toLowerCase().contains(query),
          );
        })
        .toList(growable: false);
  }

  List<DatabaseView> _filteredDatabases(List<DatabaseView> databases) {
    final query = _query.toLowerCase();
    if (query.isEmpty) return databases;
    return databases
        .where((database) {
          return [
            database.id.toString(),
            database.role,
            database.roleLabel,
            database.type,
            database.typeLabel,
            database.address,
            database.username,
          ].whereType<String>().any(
            (value) => value.toLowerCase().contains(query),
          );
        })
        .toList(growable: false);
  }

  Future<void> _createCurrent() async {
    if (_showingServers) {
      final result = await showServerEditor(context);
      if (result == null || !mounted) return;
      final store = context.read<InventoryStore>();
      final ok = await store.createServer(result.input, secret: result.secret);
      if (mounted) _reportMutation(store, ok, '服务器已创建');
      return;
    }
    final result = await showDatabaseEditor(context);
    if (result == null || !mounted) return;
    final store = context.read<InventoryStore>();
    final ok = await store.createDatabase(result.input, secret: result.secret);
    if (mounted) _reportMutation(store, ok, '数据库已创建');
  }

  Future<void> _editServer(ServerView server) async {
    final result = await showServerEditor(context, existing: server);
    if (result == null || !mounted) return;
    final store = context.read<InventoryStore>();
    final ok = await store.updateServer(
      server.id,
      result.input,
      secret: result.secret,
    );
    if (mounted) _reportMutation(store, ok, '服务器已更新');
  }

  Future<void> _deleteServer(ServerView server) async {
    final confirmed = await _confirmDelete(
      '删除服务器',
      '确定删除服务器「${server.displayLabel}」？正在被使用的资源无法删除。',
    );
    if (!confirmed || !mounted) return;
    final store = context.read<InventoryStore>();
    final ok = await store.deleteServer(server.id);
    if (mounted) _reportMutation(store, ok, '服务器已删除');
  }

  void _showServerUsage(ServerView server) {
    final store = context.read<InventoryStore>();
    showDialog<void>(
      context: context,
      builder: (_) => _UsageDialog(
        title: '服务器使用情况 · ${server.displayLabel}',
        emptyMessage: '暂无环境引用此服务器',
        load: () => store.environmentsOnServer(server.id),
        matches: (component) => component.serverId == server.id,
      ),
    );
  }

  Future<void> _editDatabase(DatabaseView database) async {
    final result = await showDatabaseEditor(context, existing: database);
    if (result == null || !mounted) return;
    final store = context.read<InventoryStore>();
    final ok = await store.updateDatabase(
      database.id,
      result.input,
      secret: result.secret,
    );
    if (mounted) _reportMutation(store, ok, '数据库已更新');
  }

  Future<void> _deleteDatabase(DatabaseView database) async {
    final confirmed = await _confirmDelete(
      '删除数据库',
      '确定删除数据库「${database.displayLabel}」？正在被使用的资源无法删除。',
    );
    if (!confirmed || !mounted) return;
    final store = context.read<InventoryStore>();
    final ok = await store.deleteDatabase(database.id);
    if (mounted) _reportMutation(store, ok, '数据库已删除');
  }

  void _showDatabaseUsage(DatabaseView database) {
    final store = context.read<InventoryStore>();
    showDialog<void>(
      context: context,
      builder: (_) => _UsageDialog(
        title: '数据库使用情况 · ${database.displayLabel}',
        emptyMessage: '暂无环境引用此数据库',
        load: () => store.environmentsUsingDatabase(database.id),
        matches: (component) => component.databaseIds.contains(database.id),
      ),
    );
  }

  Future<bool> _confirmDelete(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _reportMutation(InventoryStore store, bool ok, String success) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(ok ? success : (store.error ?? '操作失败'))),
    );
  }
}

class _InventoryGrid extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  const _InventoryGrid({required this.itemCount, required this.itemBuilder});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: itemCount,
            itemBuilder: itemBuilder,
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 230,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );
      },
    );
  }
}

class _ServerCard extends StatelessWidget {
  final ServerView server;
  final VoidCallback onUsage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ServerCard({
    required this.server,
    required this.onUsage,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      key: ValueKey('server-card-${server.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _CardTitle(id: server.id, title: server.displayLabel),
            const SizedBox(height: 12),
            _MetadataRow(label: '操作系统', value: server.osLabel),
            const SizedBox(height: 8),
            _MetadataRow(
              label: 'SSH',
              value: server.sshAddress.isEmpty ? '未配置' : server.sshAddress,
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  key: ValueKey('server-usage-${server.id}'),
                  tooltip: '查看使用情况',
                  onPressed: onUsage,
                  icon: const Icon(Icons.account_tree_outlined),
                ),
                IconButton(
                  key: ValueKey('server-edit-${server.id}'),
                  tooltip: '编辑服务器',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  key: ValueKey('server-delete-${server.id}'),
                  tooltip: '删除服务器',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DatabaseCard extends StatelessWidget {
  final DatabaseView database;
  final VoidCallback onUsage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DatabaseCard({
    required this.database,
    required this.onUsage,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      key: ValueKey('database-card-${database.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _CardTitle(id: database.id, title: database.roleLabel),
            const SizedBox(height: 12),
            _MetadataRow(label: '类型', value: database.typeLabel),
            const SizedBox(height: 8),
            _MetadataRow(
              label: '连接',
              value: database.address.isEmpty ? '未配置' : database.address,
            ),
            const SizedBox(height: 8),
            _MetadataRow(label: '用户名', value: database.username ?? '-'),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  key: ValueKey('database-usage-${database.id}'),
                  tooltip: '查看使用情况',
                  onPressed: onUsage,
                  icon: const Icon(Icons.account_tree_outlined),
                ),
                IconButton(
                  key: ValueKey('database-edit-${database.id}'),
                  tooltip: '编辑数据库',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  key: ValueKey('database-delete-${database.id}'),
                  tooltip: '删除数据库',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  final int id;
  final String title;

  const _CardTitle({required this.id, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('#$id'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _MetadataRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetadataRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
        Expanded(child: SelectableText(value)),
      ],
    );
  }
}

class _EmptyInventory extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyInventory({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _InventoryErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('inventory-error-banner'),
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: scheme.error)),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _UsageDialog extends StatefulWidget {
  final String title;
  final String emptyMessage;
  final Future<List<EnvironmentView>> Function() load;
  final bool Function(ComponentView component) matches;

  const _UsageDialog({
    required this.title,
    required this.emptyMessage,
    required this.load,
    required this.matches,
  });

  @override
  State<_UsageDialog> createState() => _UsageDialogState();
}

class _UsageDialogState extends State<_UsageDialog> {
  late Future<List<EnvironmentView>> _environments;

  @override
  void initState() {
    super.initState();
    _environments = widget.load();
  }

  void _retry() {
    final next = widget.load();
    setState(() {
      _environments = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: FutureBuilder<List<EnvironmentView>>(
          future: _environments,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 160,
                child: Center(
                  child: CircularProgressIndicator(
                    key: ValueKey('inventory-usage-loading'),
                  ),
                ),
              );
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('加载使用情况失败：${snapshot.error}'),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const ValueKey('inventory-usage-retry'),
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              );
            }
            final rows =
                <
                  ({
                    EnvironmentView environment,
                    List<ComponentView> components,
                  })
                >[];
            for (final environment
                in snapshot.data ?? const <EnvironmentView>[]) {
              final components = environment.components
                  .where(widget.matches)
                  .toList(growable: false);
              if (components.isNotEmpty) {
                rows.add((environment: environment, components: components));
              }
            }
            if (rows.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text(widget.emptyMessage)),
              );
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: rows.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  return ListTile(
                    key: ValueKey('usage-environment-${row.environment.id}'),
                    leading: Text('#${row.environment.id}'),
                    title: Text(row.environment.name),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final component in row.components)
                            Chip(
                              key: ValueKey('usage-component-${component.id}'),
                              label: Text(component.roleLabel),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
