import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../catalog/environment_store.dart';
import '../../catalog/environment_view.dart';
import '../../inventory/inventory_store.dart';
import '../../inventory/inventory_view.dart';
import '../../remote_files/remote_file_store.dart';
import '../../services/remote_file/remote_file_session.dart';
import 'open_remote_file.dart';
import 'remote_file_viewer.dart';

/// The 日志文件 page (prototype-validated 变体 A + one-click row entry): a
/// roster of components on the left for preset 日志位置 opens, a free
/// server+path bar for everything else, and each open file as a tab. Sessions
/// keep streaming while the user is elsewhere in the app.
class RemoteFilesPage extends StatefulWidget {
  const RemoteFilesPage({super.key});

  @override
  State<RemoteFilesPage> createState() => _RemoteFilesPageState();
}

class _RemoteFilesPageState extends State<RemoteFilesPage> {
  final _pathController = TextEditingController();
  RemoteFileMode _freeMode = RemoteFileMode.follow;

  /// Server picked in the free-path bar; falls back to the active tab's
  /// server, then the first known server.
  int? _freeServerId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Both stores tolerate repeat loads; the roster and the server dropdown
      // need them when this page is the first one visited.
      context.read<EnvironmentStore>().load();
      context.read<InventoryStore>().load();
    });
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<RemoteFileStore>();
    return Column(
      children: [
        PageHeader(
          title: '日志文件',
          visibleCount: store.tabs.length,
          totalCount: store.tabs.length,
        ),
        const Divider(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 320, child: _Roster(store: store)),
              const VerticalDivider(width: 1),
              Expanded(child: _buildRight(store)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRight(RemoteFileStore store) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFreePathBar(store),
        const Divider(height: 1),
        if (store.tabs.isEmpty)
          const Expanded(
            child: EmptyState(
              icon: Icons.terminal,
              message: '从左侧选择组件打开日志，或在上方输入路径打开远程文件',
            ),
          )
        else ...[
          _TabStrip(store: store),
          const Divider(height: 1),
          Expanded(
            child: RemoteFileViewer(
              key: ObjectKey(store.activeTab),
              tab: store.activeTab!,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFreePathBar(RemoteFileStore store) {
    final tokens = AppTokens.of(context);
    final inventory = context.watch<InventoryStore>();
    final servers = inventory.servers;
    final effectiveServerId = _effectiveFreeServerId(store, servers);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<int>(
              initialValue: effectiveServerId,
              isDense: true,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '服务器',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              style: tokens.mono(fontSize: 12.5),
              items: [
                for (final s in servers)
                  DropdownMenuItem(
                    value: s.id,
                    child: Text(
                      s.displayLabel,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (id) => setState(() => _freeServerId = id),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _pathController,
              style: tokens.mono(fontSize: 12.5),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: '/path/to/remote/file — 任意远程文件路径',
              ),
              onSubmitted: (_) => _openFreePath(store, effectiveServerId),
            ),
          ),
          const SizedBox(width: 8),
          SegmentedButton<RemoteFileMode>(
            segments: const [
              ButtonSegment(value: RemoteFileMode.follow, label: Text('跟随')),
              ButtonSegment(value: RemoteFileMode.view, label: Text('查看')),
            ],
            selected: {_freeMode},
            onSelectionChanged: (s) => setState(() => _freeMode = s.first),
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            showSelectedIcon: false,
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: effectiveServerId == null
                ? null
                : () => _openFreePath(store, effectiveServerId),
            child: const Text('打开'),
          ),
        ],
      ),
    );
  }

  int? _effectiveFreeServerId(RemoteFileStore store, List<ServerView> servers) {
    if (servers.isEmpty) return null;
    final ids = servers.map((s) => s.id).toSet();
    if (_freeServerId != null && ids.contains(_freeServerId)) {
      return _freeServerId;
    }
    final activeServerId = store.activeTab?.serverId;
    if (activeServerId != null && ids.contains(activeServerId)) {
      return activeServerId;
    }
    return servers.first.id;
  }

  Future<void> _openFreePath(RemoteFileStore store, int? serverId) async {
    final path = _pathController.text.trim();
    if (serverId == null || path.isEmpty) return;
    final inventory = context.read<InventoryStore>();
    final label = inventory.serversById[serverId]?.displayLabel ?? '#$serverId';
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    final name = segments.isEmpty ? path : segments.last;
    await openRemoteFile(
      context,
      store: store,
      serverId: serverId,
      title: '$label · $name',
      path: path,
      mode: _freeMode,
    );
  }
}

/// Preset opens: every component that runs on a Server, grouped by
/// environment. Enabled rows open the component's 日志位置 in follow mode.
class _Roster extends StatelessWidget {
  final RemoteFileStore store;

  const _Roster({required this.store});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final envStore = context.watch<EnvironmentStore>();

    final rows = <Widget>[];
    for (final env in envStore.environments) {
      final hosted = env.components.where((c) => c.serverId != null).toList();
      if (hosted.isEmpty) continue;
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
        child: Text(
          env.name,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis,
        ),
      ));
      for (final c in hosted) {
        rows.add(_RosterRow(env: env, component: c, store: store));
      }
    }

    if (rows.isEmpty) {
      return const EmptyState(
        icon: Icons.article_outlined,
        message: '暂无关联了服务器的组件',
      );
    }
    // Material, not ColoredBox: the ListTile rows paint their ink on it.
    return Material(
      color: tokens.rosterBg,
      child: ListView(children: rows),
    );
  }
}

class _RosterRow extends StatelessWidget {
  final EnvironmentView env;
  final ComponentView component;
  final RemoteFileStore store;

  const _RosterRow({
    required this.env,
    required this.component,
    required this.store,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final hasLog = component.logLocation?.isNotEmpty == true;
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      enabled: hasLog,
      leading: Icon(
        Icons.article_outlined,
        size: 16,
        color: hasLog ? tokens.accent : tokens.border,
      ),
      title: Text(component.roleLabel, style: const TextStyle(fontSize: 12.5)),
      subtitle: Text(
        hasLog ? component.logLocation! : '未配置日志位置',
        style: tokens.mono(fontSize: 10.5, color: tokens.textSecondary),
        overflow: TextOverflow.ellipsis,
      ),
      onTap: hasLog
          ? () => openRemoteFile(
                context,
                store: store,
                serverId: component.serverId!,
                title: '${env.name} · ${component.roleLabel}',
                path: component.logLocation!,
                mode: RemoteFileMode.follow,
              )
          : null,
    );
  }
}

class _TabStrip extends StatelessWidget {
  final RemoteFileStore store;

  const _TabStrip({required this.store});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return SizedBox(
      height: 34,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: store.tabs.length,
        itemBuilder: (context, i) {
          final tab = store.tabs[i];
          final active = i == store.activeIndex;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTokens.radiusControl),
              onTap: () => store.select(i),
              child: Container(
                padding: const EdgeInsets.only(left: 10, right: 4),
                decoration: BoxDecoration(
                  color: active ? tokens.selectionBg : null,
                  borderRadius: BorderRadius.circular(AppTokens.radiusControl),
                  border: Border.all(
                    color: active ? tokens.selectionBorder : tokens.border,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      tab.session.mode == RemoteFileMode.follow
                          ? Icons.play_arrow
                          : Icons.description_outlined,
                      size: 13,
                      color: tokens.accent,
                    ),
                    const SizedBox(width: 5),
                    Text(tab.title, style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 2),
                    IconButton(
                      icon: const Icon(Icons.close, size: 13),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 22, minHeight: 22),
                      onPressed: () => store.close(i),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
