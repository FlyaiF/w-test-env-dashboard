import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../catalog/environment_store.dart';
import '../../catalog/environment_view.dart';
import '../../inventory/inventory_store.dart';
import '../../inventory/inventory_view.dart';
import '../../remote_files/path_suggestions.dart';
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
  final _pathFocus = FocusNode();
  final _pathScroll = ScrollController();

  /// Directory listings borrowed from live sessions, memoized as futures per
  /// `serverId:dir`: a typing burst shares the in-flight request instead of
  /// firing one listdir per keystroke, and a completed success is reused for
  /// the page's lifetime. Empty results (incl. failures — listDirectory never
  /// throws) are evicted on completion so a later attempt can retry.
  final _dirCache = <String, Future<List<String>>>{};

  RemoteFileMode _freeMode = RemoteFileMode.follow;

  /// Server picked in the free-path bar; falls back to the active tab's
  /// server, then the first known server.
  int? _freeServerId;

  /// Last path this page auto-filled from the active tab. Lets tab switches
  /// keep the bar in sync while never clobbering a hand-edited value: the
  /// field is only rewritten while it is empty or still holds our own fill.
  String? _autoFilledPath;

  /// Seed the free-path bar with the active tab's path so opening a sibling
  /// file is an edit of the tail, not a full retype.
  void _syncPathToActiveTab(RemoteFileStore store) {
    final activePath = store.activeTab?.session.path;
    if (activePath == null || activePath.isEmpty) return;
    final current = _pathController.text.trim();
    if (current.isNotEmpty && current != _autoFilledPath) return;
    _autoFilledPath = activePath;
    if (current == activePath) return;
    _pathController.value = TextEditingValue(
      text: activePath,
      selection: TextSelection.collapsed(offset: activePath.length),
    );
    _scrollPathToEnd();
  }

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
    _pathFocus.dispose();
    _pathScroll.dispose();
    super.dispose();
  }

  /// A long path overflows the bar head-first, hiding the filename — the part
  /// that matters. After any programmatic fill, pin the viewport to the tail
  /// (typing keeps it there anyway, since the caret sits at the end).
  void _scrollPathToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pathScroll.hasClients) return;
      _pathScroll.jumpTo(_pathScroll.position.maxScrollExtent);
    });
  }

  /// Paths the app already knows for [serverId]: open-tab paths first (the
  /// user's current working set), then component 日志位置 presets.
  List<String> _knownPathsFor(RemoteFileStore store, int? serverId) {
    if (serverId == null) return const [];
    final paths = <String>[];
    for (final tab in store.tabs) {
      if (tab.serverId == serverId && !paths.contains(tab.session.path)) {
        paths.add(tab.session.path);
      }
    }
    for (final env in context.read<EnvironmentStore>().environments) {
      for (final c in env.components) {
        final log = c.logLocation;
        if (c.serverId == serverId &&
            log != null &&
            log.isNotEmpty &&
            !paths.contains(log)) {
          paths.add(log);
        }
      }
    }
    return paths;
  }

  Future<List<String>> _pathSuggestions(
    RemoteFileStore store,
    int? serverId,
    String input,
  ) {
    final session = serverId == null ? null : store.liveSessionFor(serverId);
    DirectoryLister? lister;
    if (session != null) {
      lister = (dir) {
        final key = '$serverId:$dir';
        final cached = _dirCache[key];
        if (cached != null) return cached;
        final future = session.listDirectory(dir);
        _dirCache[key] = future;
        future.then((entries) {
          if (entries.isEmpty) _dirCache.remove(key);
        });
        return future;
      };
    }
    return buildPathSuggestions(
      input: input,
      knownPaths: _knownPathsFor(store, serverId),
      listDirectory: lister,
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<RemoteFileStore>();
    _syncPathToActiveTab(store);
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
            child: RawAutocomplete<String>(
              textEditingController: _pathController,
              focusNode: _pathFocus,
              optionsBuilder: (value) =>
                  _pathSuggestions(store, effectiveServerId, value.text),
              onSelected: (_) => _scrollPathToEnd(),
              optionsViewBuilder: (context, onSelected, options) =>
                  _SuggestionOverlay(
                    options: options,
                    onSelected: onSelected,
                    onDirectoryPicked: _continueWalkInto,
                  ),
              fieldViewBuilder: (context, controller, focusNode, _) {
                // Enter always opens the typed path; suggestions are picked by
                // click so completion can never hijack a deliberate open.
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  scrollController: _pathScroll,
                  style: tokens.mono(fontSize: 12.5),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: '/path/to/remote/file — 关键字或路径，自动补全',
                  ),
                  onSubmitted: (_) => _openFreePath(store, effectiveServerId),
                );
              },
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

  /// A picked directory continues the walk instead of ending it. Filling the
  /// field directly — rather than through RawAutocomplete's onSelected, which
  /// records a selection and hides the overlay until the next keystroke —
  /// makes the text change re-query suggestions, so the overlay immediately
  /// lists the chosen directory's contents. Only picking a file completes.
  void _continueWalkInto(String dirPath) {
    _pathController.value = TextEditingValue(
      text: dirPath,
      selection: TextSelection.collapsed(offset: dirPath.length),
    );
    _scrollPathToEnd();
  }

  Future<void> _openFreePath(RemoteFileStore store, int? serverId) async {
    final path = _pathController.text.trim();
    if (serverId == null || path.isEmpty) return;
    final inventory = context.read<InventoryStore>();
    final label = inventory.serversById[serverId]?.displayLabel ?? '#$serverId';
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    final name = segments.isEmpty ? path : segments.last;
    // The typed path is now the active tab's path; treat it as our own fill so
    // later tab switches keep syncing instead of seeing it as a hand edit.
    _autoFilledPath = path;
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

/// The autocomplete dropdown for the free-path bar: a compact mono list of
/// completed paths. Directories end in `/` and route through
/// [onDirectoryPicked] so the overlay stays open on that directory's
/// contents; only picking a file ([onSelected]) ends the completion.
class _SuggestionOverlay extends StatelessWidget {
  final Iterable<String> options;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onDirectoryPicked;

  const _SuggestionOverlay({
    required this.options,
    required this.onSelected,
    required this.onDirectoryPicked,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260, maxWidth: 560),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (context, i) {
              final option = options.elementAt(i);
              final isDir = option.endsWith('/');
              // Rows differ in their tail, so the tail leads: name first,
              // parent directory dimmed after it (an end-ellipsis on the full
              // path would render every sibling identical).
              final stem =
                  isDir ? option.substring(0, option.length - 1) : option;
              final cut = stem.lastIndexOf('/');
              final name =
                  cut < 0 ? option : '${stem.substring(cut + 1)}${isDir ? '/' : ''}';
              final dir = cut < 0 ? '' : stem.substring(0, cut + 1);
              return InkWell(
                onTap: () =>
                    isDir ? onDirectoryPicked(option) : onSelected(option),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Row(
                    children: [
                      Icon(
                        isDir ? Icons.folder_outlined : Icons.description_outlined,
                        size: 14,
                        color: tokens.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          name,
                          style: tokens.mono(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (dir.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            dir,
                            style: tokens.mono(
                              fontSize: 11,
                              color: tokens.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
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
