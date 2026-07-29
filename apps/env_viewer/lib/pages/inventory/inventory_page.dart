import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../catalog/environment_view.dart';
import '../../inventory/inventory_store.dart';
import '../../inventory/inventory_view.dart';
import 'inventory_editors.dart';

/// Standalone presentation for the shared Server/Database Resource Inventory:
/// one dense, client-side-sortable table per tab (服务器 / 数据库). The 引用
/// count is the clickable affordance that opens the usage view. Routing is
/// intentionally owned by the application shell, not this page.
class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

enum _ServerColumn { id, host, os, ssh, password, references }

enum _DatabaseColumn {
  id,
  role,
  type,
  connection,
  username,
  password,
  references,
}

class _InventoryPageState extends State<InventoryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchController = TextEditingController();
  Timer? _debounce;
  int _activeTab = 0;

  _ServerColumn _serverSort = _ServerColumn.id;
  bool _serverAscending = true;
  _DatabaseColumn _databaseSort = _DatabaseColumn.id;
  bool _databaseAscending = true;

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
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Switching tabs keeps the search query — one query filters both
  /// inventories (the store owns it).
  void _handleTabChange() {
    if (_activeTab == _tabController.index) return;
    setState(() => _activeTab = _tabController.index);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<InventoryStore>();
    final servers = _sortedServers(store.filteredServers);
    final databases = _sortedDatabases(store.filteredDatabases);
    final visibleCount = _showingServers ? servers.length : databases.length;
    final totalCount = _showingServers
        ? store.servers.length
        : store.databases.length;

    return Column(
      children: [
        PageHeader(
          title: '资源清单',
          visibleCount: visibleCount,
          totalCount: totalCount,
          search: FilterHistoryTextField(
            key: const ValueKey('inventory-search-field'),
            controller: _searchController,
            filterText: _searchController.text,
            hintText: '搜索主机、系统、SSH、用途、类型、地址、用户名...',
            onChanged: (value) {
              setState(() {});
              _debounce?.cancel();
              if (value.trim().isEmpty) {
                store.setSearch('');
                return;
              }
              _debounce = Timer(const Duration(milliseconds: 250), () {
                store.setSearch(value);
              });
            },
          ),
          actions: [
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
        ),
        if (store.error != null)
          ErrorBanner(
            key: const ValueKey('inventory-error-banner'),
            message: store.error!,
            onRetry: store.load,
          ),
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '服务器'),
            Tab(text: '数据库'),
          ],
        ),
        SizedBox(
          height: 3,
          child: store.loading && store.loaded
              ? const LinearProgressIndicator(minHeight: 3)
              : null,
        ),
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

  // ---- sorting ----------------------------------------------------------

  List<ServerView> _sortedServers(List<ServerView> servers) {
    final sorted = [...servers];
    final dir = _serverAscending ? 1 : -1;
    int byLabel(String a, String b) =>
        a.toLowerCase().compareTo(b.toLowerCase());
    sorted.sort((a, b) {
      final order = switch (_serverSort) {
        _ServerColumn.id => a.id.compareTo(b.id),
        _ServerColumn.host => byLabel(a.displayLabel, b.displayLabel),
        _ServerColumn.os => byLabel(a.osLabel, b.osLabel),
        _ServerColumn.ssh => byLabel(a.sshAddress, b.sshAddress),
        _ServerColumn.password => (a.hasSecret ? 1 : 0).compareTo(
          b.hasSecret ? 1 : 0,
        ),
        _ServerColumn.references => a.referenceCount.compareTo(
          b.referenceCount,
        ),
      };
      return dir * (order != 0 ? order : a.id.compareTo(b.id));
    });
    return sorted;
  }

  List<DatabaseView> _sortedDatabases(List<DatabaseView> databases) {
    final sorted = [...databases];
    final dir = _databaseAscending ? 1 : -1;
    int byLabel(String a, String b) =>
        a.toLowerCase().compareTo(b.toLowerCase());
    sorted.sort((a, b) {
      final order = switch (_databaseSort) {
        _DatabaseColumn.id => a.id.compareTo(b.id),
        _DatabaseColumn.role => byLabel(a.roleLabel, b.roleLabel),
        _DatabaseColumn.type => byLabel(a.typeLabel, b.typeLabel),
        _DatabaseColumn.connection => byLabel(a.address, b.address),
        _DatabaseColumn.username => byLabel(a.username ?? '', b.username ?? ''),
        _DatabaseColumn.password => (a.hasSecret ? 1 : 0).compareTo(
          b.hasSecret ? 1 : 0,
        ),
        _DatabaseColumn.references => a.referenceCount.compareTo(
          b.referenceCount,
        ),
      };
      return dir * (order != 0 ? order : a.id.compareTo(b.id));
    });
    return sorted;
  }

  void _sortServersBy(_ServerColumn column) {
    setState(() {
      if (_serverSort == column) {
        _serverAscending = !_serverAscending;
      } else {
        _serverSort = column;
        _serverAscending = true;
      }
    });
  }

  void _sortDatabasesBy(_DatabaseColumn column) {
    setState(() {
      if (_databaseSort == column) {
        _databaseAscending = !_databaseAscending;
      } else {
        _databaseSort = column;
        _databaseAscending = true;
      }
    });
  }

  // ---- bodies -----------------------------------------------------------

  Widget _buildServerBody(InventoryStore store, List<ServerView> servers) {
    if (store.loading && !store.loaded) {
      return const Center(
        child: CircularProgressIndicator(
          key: ValueKey('inventory-initial-loading'),
        ),
      );
    }
    if (servers.isEmpty) {
      return EmptyState(
        icon: store.search.isEmpty ? Icons.dns_outlined : Icons.search_off,
        message: store.search.isEmpty ? '暂无服务器' : '没有匹配的服务器',
      );
    }
    return _InventoryTable(
      minWidth: 680,
      header: _ServerTableHeader(
        sort: _serverSort,
        ascending: _serverAscending,
        onSort: _sortServersBy,
      ),
      itemCount: servers.length,
      itemBuilder: (context, index) {
        final server = servers[index];
        return _ServerRow(
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
      return EmptyState(
        icon: store.search.isEmpty ? Icons.storage_outlined : Icons.search_off,
        message: store.search.isEmpty ? '暂无数据库' : '没有匹配的数据库',
      );
    }
    return _InventoryTable(
      minWidth: 780,
      header: _DatabaseTableHeader(
        sort: _databaseSort,
        ascending: _databaseAscending,
        onSort: _sortDatabasesBy,
      ),
      itemCount: databases.length,
      itemBuilder: (context, index) {
        final database = databases[index];
        return _DatabaseRow(
          database: database,
          onUsage: () => _showDatabaseUsage(database),
          onEdit: () => _editDatabase(database),
          onDelete: () => _deleteDatabase(database),
        );
      },
    );
  }

  // ---- mutations --------------------------------------------------------

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

// ---- table shell ---------------------------------------------------------

/// Column plan shared by the header and every row so cells stay aligned.
/// Fixed pixel widths for compact columns; host/connection flex the rest.
abstract final class _Cols {
  static const double id = 56;
  static const double os = 100;
  static const double type = 96;
  static const double role = 110;
  static const double username = 110;
  static const double password = 72;
  static const double references = 56;
  static const double actions = 84;
  static const double gap = 8;
}

class _InventoryTable extends StatelessWidget {
  final Widget header;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// Below this width the table scrolls horizontally instead of squeezing its
  /// fixed data columns.
  final double minWidth;

  const _InventoryTable({
    required this.header,
    required this.itemCount,
    required this.itemBuilder,
    required this.minWidth,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final needsScroll = constraints.maxWidth < minWidth;
        final table = SizedBox(
          width: needsScroll ? minWidth : constraints.maxWidth,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: header,
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  itemCount: itemCount,
                  itemBuilder: itemBuilder,
                ),
              ),
            ],
          ),
        );
        if (!needsScroll) return table;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: table,
        );
      },
    );
  }
}

/// Sortable header cell: click cycles the sort; the active column shows an
/// ascending/descending arrow.
class _HeaderCell extends StatelessWidget {
  final String label;
  final double? width;
  final bool active;
  final bool ascending;
  final VoidCallback onTap;

  const _HeaderCell({
    required this.label,
    this.width,
    required this.active,
    required this.ascending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final cell = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusChip),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: active ? tokens.accent : tokens.textSecondary,
                ),
              ),
            ),
            if (active)
              Icon(
                ascending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 11,
                color: tokens.accent,
              ),
          ],
        ),
      ),
    );
    return width == null
        ? Expanded(child: cell)
        : SizedBox(
            width: width,
            child: Align(alignment: Alignment.centerLeft, child: cell),
          );
  }
}

class _HeaderBar extends StatelessWidget {
  final List<Widget> cells;

  const _HeaderBar({required this.cells});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tokens.tableHeaderBg,
        borderRadius: BorderRadius.circular(AppTokens.radiusControl),
      ),
      child: Row(children: cells),
    );
  }
}

class _ServerTableHeader extends StatelessWidget {
  final _ServerColumn sort;
  final bool ascending;
  final ValueChanged<_ServerColumn> onSort;

  const _ServerTableHeader({
    required this.sort,
    required this.ascending,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, _ServerColumn column, {double? width}) =>
        _HeaderCell(
          label: label,
          width: width,
          active: sort == column,
          ascending: ascending,
          onTap: () => onSort(column),
        );
    return _HeaderBar(
      cells: [
        cell('ID', _ServerColumn.id, width: _Cols.id),
        cell('主机', _ServerColumn.host),
        const SizedBox(width: _Cols.gap),
        cell('操作系统', _ServerColumn.os, width: _Cols.os),
        cell('SSH 地址', _ServerColumn.ssh),
        const SizedBox(width: _Cols.gap),
        cell('密码', _ServerColumn.password, width: _Cols.password),
        cell('引用', _ServerColumn.references, width: _Cols.references),
        const SizedBox(width: _Cols.actions),
      ],
    );
  }
}

class _DatabaseTableHeader extends StatelessWidget {
  final _DatabaseColumn sort;
  final bool ascending;
  final ValueChanged<_DatabaseColumn> onSort;

  const _DatabaseTableHeader({
    required this.sort,
    required this.ascending,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, _DatabaseColumn column, {double? width}) =>
        _HeaderCell(
          label: label,
          width: width,
          active: sort == column,
          ascending: ascending,
          onTap: () => onSort(column),
        );
    return _HeaderBar(
      cells: [
        cell('ID', _DatabaseColumn.id, width: _Cols.id),
        cell('用途', _DatabaseColumn.role, width: _Cols.role),
        cell('类型', _DatabaseColumn.type, width: _Cols.type),
        cell('连接', _DatabaseColumn.connection),
        const SizedBox(width: _Cols.gap),
        cell('用户名', _DatabaseColumn.username, width: _Cols.username),
        cell('密码', _DatabaseColumn.password, width: _Cols.password),
        cell('引用', _DatabaseColumn.references, width: _Cols.references),
        const SizedBox(width: _Cols.actions),
      ],
    );
  }
}

// ---- rows ----------------------------------------------------------------

class _TableRowShell extends StatelessWidget {
  final Key? rowKey;
  final List<Widget> cells;

  const _TableRowShell({this.rowKey, required this.cells});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      key: rowKey,
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: tokens.cardBg,
        borderRadius: BorderRadius.circular(AppTokens.radiusRow),
        border: Border.all(color: tokens.cardBorder),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTokens.radiusRow),
          hoverColor: tokens.hover,
          onTap: null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(children: cells),
          ),
        ),
      ),
    );
  }
}

/// 已设置 / 未设置 password presence chip.
class _SecretChip extends StatelessWidget {
  final bool hasSecret;

  const _SecretChip({required this.hasSecret});

  @override
  Widget build(BuildContext context) {
    return StatusChip(
      kind: hasSecret ? StatusChipKind.ok : StatusChipKind.none,
      label: hasSecret ? '已设置' : '未设置',
    );
  }
}

/// The 引用 count itself is the clickable affordance opening the usage view.
class _ReferenceCountButton extends StatelessWidget {
  final Key? buttonKey;
  final int count;
  final VoidCallback onTap;

  const _ReferenceCountButton({
    this.buttonKey,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Tooltip(
        message: '查看使用情况',
        child: InkWell(
          key: buttonKey,
          borderRadius: BorderRadius.circular(AppTokens.radiusChip),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Text(
              '$count',
              style: tokens.mono(
                fontSize: 12.5,
                color: tokens.accent,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServerRow extends StatelessWidget {
  final ServerView server;
  final VoidCallback onUsage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ServerRow({
    required this.server,
    required this.onUsage,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return _TableRowShell(
      rowKey: ValueKey('server-card-${server.id}'),
      cells: [
        SizedBox(
          width: _Cols.id,
          child: Text(
            '#${server.id}',
            style: tokens.mono(fontSize: 12.5, color: tokens.textSecondary),
          ),
        ),
        Expanded(
          child: Text(
            server.displayLabel,
            style: tokens.mono(fontSize: 12.5, weight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: _Cols.gap),
        SizedBox(
          width: _Cols.os,
          child: Text(server.osLabel, style: const TextStyle(fontSize: 12.5)),
        ),
        Expanded(
          child: Text(
            server.sshAddress.isEmpty ? '-' : server.sshAddress,
            style: tokens.mono(fontSize: 12.5),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: _Cols.gap),
        SizedBox(
          width: _Cols.password,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _SecretChip(hasSecret: server.hasSecret),
          ),
        ),
        SizedBox(
          width: _Cols.references,
          child: _ReferenceCountButton(
            buttonKey: ValueKey('server-usage-${server.id}'),
            count: server.referenceCount,
            onTap: onUsage,
          ),
        ),
        SizedBox(
          width: _Cols.actions,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                key: ValueKey('server-edit-${server.id}'),
                tooltip: '编辑服务器',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                key: ValueKey('server-delete-${server.id}'),
                tooltip: '删除服务器',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                onPressed: onDelete,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DatabaseRow extends StatelessWidget {
  final DatabaseView database;
  final VoidCallback onUsage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DatabaseRow({
    required this.database,
    required this.onUsage,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return _TableRowShell(
      rowKey: ValueKey('database-card-${database.id}'),
      cells: [
        SizedBox(
          width: _Cols.id,
          child: Text(
            '#${database.id}',
            style: tokens.mono(fontSize: 12.5, color: tokens.textSecondary),
          ),
        ),
        SizedBox(
          width: _Cols.role,
          child: Text(
            database.roleLabel,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(
          width: _Cols.type,
          child: Text(
            database.typeLabel,
            style: const TextStyle(fontSize: 12.5),
          ),
        ),
        Expanded(
          child: Text(
            database.address.isEmpty ? '-' : database.address,
            style: tokens.mono(fontSize: 12.5),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: _Cols.gap),
        SizedBox(
          width: _Cols.username,
          child: Text(
            database.username ?? '-',
            style: tokens.mono(fontSize: 12.5),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(
          width: _Cols.password,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _SecretChip(hasSecret: database.hasSecret),
          ),
        ),
        SizedBox(
          width: _Cols.references,
          child: _ReferenceCountButton(
            buttonKey: ValueKey('database-usage-${database.id}'),
            count: database.referenceCount,
            onTap: onUsage,
          ),
        ),
        SizedBox(
          width: _Cols.actions,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                key: ValueKey('database-edit-${database.id}'),
                tooltip: '编辑数据库',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                key: ValueKey('database-delete-${database.id}'),
                tooltip: '删除数据库',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                onPressed: onDelete,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ],
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
