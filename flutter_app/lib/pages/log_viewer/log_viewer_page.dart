import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/config_service.dart';
import '../../models/env_info.dart';
import '../../services/env_service.dart';
import '../../services/ssh_service.dart';
import '../../utils/addr_parser.dart';

class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => LogViewerPageState();
}

class LogViewerPageState extends State<LogViewerPage> {
  final List<_LogTab> _tabs = [];
  final _envSearchController = TextEditingController();
  int _activeTabIndex = 0;
  int? _selectedEnvNo;

  void _addTab(EnvInfo env, String username, String password) {
    final existingIndex = _tabs.indexWhere((tab) => tab.env.eNo == env.eNo);
    if (existingIndex >= 0) {
      setState(() {
        _activeTabIndex = existingIndex;
        _selectedEnvNo = env.eNo;
      });
      return;
    }

    final parsed = parseServerAddr(env.eWebserveraddr ?? '');
    final session = SshLogSession(
      host: parsed.host,
      port: parsed.port,
      logPath: env.eWeblogpath ?? '',
    );
    final tab = _LogTab(
      name: env.eName ?? '环境#${env.eNo}',
      session: session,
      env: env,
    );

    setState(() {
      _tabs.add(tab);
      _activeTabIndex = _tabs.length - 1;
      _selectedEnvNo = env.eNo;
    });

    session.connect(username: username, password: password).catchError((e) {
      // Error is exposed inside the session stream.
    });
  }

  Future<void> connectToEnv(EnvInfo env) async {
    final config = await ConfigService.load();
    final parsed = parseServerAddr(env.eWebserveraddr ?? '');
    final username = parsed.username ?? config.ssh.defaultUsername;
    final password = parsed.password ?? config.ssh.defaultPassword;
    _addTab(env, username, password);
  }

  void _closeTab(int index) {
    _tabs[index].session.disconnect();
    setState(() {
      _tabs.removeAt(index);
      if (_tabs.isEmpty) {
        _activeTabIndex = 0;
      } else {
        _activeTabIndex = index.clamp(0, _tabs.length - 1);
      }
    });
  }

  Future<void> _showCredentialDialog(EnvInfo env) async {
    final config = await ConfigService.load();
    final parsed = parseServerAddr(env.eWebserveraddr ?? '');
    final usernameCtrl = TextEditingController(
      text: parsed.username ?? config.ssh.defaultUsername,
    );
    final passwordCtrl = TextEditingController(
      text: parsed.password ?? config.ssh.defaultPassword,
    );

    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('连接 ${env.eName ?? "#${env.eNo}"}'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DialogMetaRow(
                label: '服务器',
                value: '${parsed.host}:${parsed.port}',
              ),
              _DialogMetaRow(label: '日志路径', value: env.eWeblogpath ?? '-'),
              const SizedBox(height: 12),
              TextField(
                controller: usernameCtrl,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '密码',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.terminal),
            label: const Text('连接'),
          ),
        ],
      ),
    );

    if (result == true) {
      _addTab(env, usernameCtrl.text.trim(), passwordCtrl.text);
    }

    usernameCtrl.dispose();
    passwordCtrl.dispose();
  }

  @override
  void dispose() {
    for (final tab in _tabs) {
      tab.session.disconnect();
    }
    _envSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final envService = context.watch<EnvService>();
    final envs = envService.logCapableEnvs;
    final filteredEnvs = _filteredEnvs(envs);
    final selectedEnv = _selectedEnv(filteredEnvs);
    final activeTab = _tabs.isEmpty ? null : _tabs[_activeTabIndex];

    return Column(
      children: [
        _buildHeader(envs.length, filteredEnvs.length),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 980;
              if (compact) {
                return Column(
                  children: [
                    SizedBox(
                      height: 260,
                      child: _buildEnvironmentPane(filteredEnvs, selectedEnv),
                    ),
                    const Divider(height: 1),
                    Expanded(child: _buildLogWorkspace(activeTab, selectedEnv)),
                  ],
                );
              }
              return Row(
                children: [
                  SizedBox(
                    width: 360,
                    child: _buildEnvironmentPane(filteredEnvs, selectedEnv),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: _buildLogWorkspace(activeTab, selectedEnv)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(int totalLogCapable, int visibleCount) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        children: [
          Text('日志查看', style: theme.textTheme.headlineSmall),
          const SizedBox(width: 12),
          Text(
            '可连接 $visibleCount / $totalLogCapable 个环境',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const Spacer(),
          if (_tabs.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                for (final tab in _tabs) {
                  tab.session.disconnect();
                }
                setState(() {
                  _tabs.clear();
                  _activeTabIndex = 0;
                });
              },
              icon: const Icon(Icons.close),
              label: const Text('关闭全部'),
            ),
        ],
      ),
    );
  }

  Widget _buildEnvironmentPane(List<EnvInfo> envs, EnvInfo? selectedEnv) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _envSearchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _envSearchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: '清空搜索',
                      onPressed: () {
                        _envSearchController.clear();
                        setState(() {});
                      },
                    ),
              hintText: '搜索环境、主机、日志路径...',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: envs.isEmpty
              ? Center(
                  child: Text(
                    '没有可连接的日志环境',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  itemCount: envs.length,
                  itemBuilder: (context, index) {
                    final env = envs[index];
                    final parsed = parseServerAddr(env.eWebserveraddr ?? '');
                    final selected = selectedEnv?.eNo == env.eNo;
                    final open = _tabs.any((tab) => tab.env.eNo == env.eNo);
                    return _LogEnvTile(
                      env: env,
                      host: parsed.host,
                      port: parsed.port,
                      selected: selected,
                      open: open,
                      onTap: () => setState(() => _selectedEnvNo = env.eNo),
                      onConnect: () => connectToEnv(env),
                      onCredentialConnect: () => _showCredentialDialog(env),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildLogWorkspace(_LogTab? activeTab, EnvInfo? selectedEnv) {
    if (activeTab == null) {
      return _LogEmptyState(
        env: selectedEnv,
        onConnect: selectedEnv == null ? null : () => connectToEnv(selectedEnv),
        onCredentialConnect: selectedEnv == null
            ? null
            : () => _showCredentialDialog(selectedEnv),
      );
    }

    return Column(
      children: [
        _buildSessionStrip(),
        const Divider(height: 1),
        Expanded(
          child: _LogPanel(
            key: ValueKey(activeTab.env.eNo),
            session: activeTab.session,
          ),
        ),
      ],
    );
  }

  Widget _buildSessionStrip() {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: _tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = _tabs[index];
          return InputChip(
            selected: index == _activeTabIndex,
            avatar: const Icon(Icons.terminal, size: 18),
            label: Text(tab.name),
            onSelected: (_) => setState(() => _activeTabIndex = index),
            deleteIcon: const Icon(Icons.close, size: 16),
            onDeleted: () => _closeTab(index),
          );
        },
      ),
    );
  }

  List<EnvInfo> _filteredEnvs(List<EnvInfo> envs) {
    final q = _envSearchController.text.trim().toLowerCase();
    if (q.isEmpty) return envs;
    return envs.where((env) {
      final parsed = parseServerAddr(env.eWebserveraddr ?? '');
      final values = [
        '${env.eNo}',
        env.eName,
        parsed.host,
        '${parsed.port}',
        env.eWebserveraddr,
        env.eWeblogpath,
      ].whereType<String>().map((value) => value.toLowerCase());
      return values.any((value) => value.contains(q));
    }).toList();
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
}

class _LogEnvTile extends StatelessWidget {
  final EnvInfo env;
  final String host;
  final int port;
  final bool selected;
  final bool open;
  final VoidCallback onTap;
  final VoidCallback onConnect;
  final VoidCallback onCredentialConnect;

  const _LogEnvTile({
    required this.env,
    required this.host,
    required this.port,
    required this.selected,
    required this.open,
    required this.onTap,
    required this.onConnect,
    required this.onCredentialConnect,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.38)
          : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.45)
              : colorScheme.outlineVariant,
        ),
      ),
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
                  Expanded(
                    child: Text(
                      env.eName ?? '环境 #${env.eNo}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (open)
                    Icon(
                      Icons.check_circle,
                      size: 18,
                      color: Colors.green.shade700,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _tileMeta(Icons.dns_outlined, '$host:$port'),
              const SizedBox(height: 4),
              _tileMeta(Icons.article_outlined, env.eWeblogpath ?? '-'),
              const SizedBox(height: 10),
              Row(
                children: [
                  FilledButton.tonalIcon(
                    onPressed: onConnect,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('连接'),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: onCredentialConnect,
                    icon: const Icon(Icons.key),
                    tooltip: '使用指定账号连接',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tileMeta(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade700),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ),
      ],
    );
  }
}

class _LogEmptyState extends StatelessWidget {
  final EnvInfo? env;
  final VoidCallback? onConnect;
  final VoidCallback? onCredentialConnect;

  const _LogEmptyState({
    required this.env,
    required this.onConnect,
    required this.onCredentialConnect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terminal, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              env == null ? '选择一个环境开始查看日志' : env!.eName ?? '环境 #${env!.eNo}',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              env == null
                  ? '左侧只显示已配置 Web 服务地址和日志路径的环境。'
                  : env!.eWeblogpath ?? '-',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            if (env != null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: onConnect,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('连接日志'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onCredentialConnect,
                    icon: const Icon(Icons.key),
                    label: const Text('指定账号'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _DialogMetaRow extends StatelessWidget {
  final String label;
  final String value;

  const _DialogMetaRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _LogTab {
  final String name;
  final SshLogSession session;
  final EnvInfo env;

  _LogTab({required this.name, required this.session, required this.env});
}

class _LogPanel extends StatefulWidget {
  final SshLogSession session;
  const _LogPanel({super.key, required this.session});

  @override
  State<_LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<_LogPanel> {
  final ScrollController _scrollController = ScrollController();
  final ScrollController _selectableVerticalController = ScrollController();
  final ScrollController _selectableHorizontalController = ScrollController();
  final TextEditingController _logSearchController = TextEditingController();
  final FocusNode _selectableFocusNode = FocusNode();
  int _totalLineCount = 0;
  final Map<int, String> _lineCache = {};
  int _displayOffset = 0;
  bool _loadingChunk = false;
  bool _autoScroll = true;
  bool _selectionMode = false;
  bool _showErrorsOnly = false;
  bool _showWarningsOnly = false;
  bool _loadingSelectableText = false;
  String? _selectableLogText;
  String? _selectableRangeLabel;
  StreamSubscription? _logSub;
  StreamSubscription? _statusSub;
  late SshSessionStatus _status;

  static const int _chunkSize = 200;
  static const double _lineExtent = 16.8;
  static const int _selectionContextLines = 1000;

  int get _visibleCount => _totalLineCount - _displayOffset;
  bool get _hasLogFilter =>
      _logSearchController.text.trim().isNotEmpty ||
      _showErrorsOnly ||
      _showWarningsOnly;

  List<int> get _filteredLineIndexes {
    final indexes =
        _lineCache.keys.where((index) => index >= _displayOffset).toList()
          ..sort();
    return indexes
        .where((index) => _lineMatchesFilters(_lineCache[index] ?? ''))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _status = widget.session.status;
    _totalLineCount = widget.session.totalLineCount;
    final tail = widget.session.buffer;
    final tailStart = _totalLineCount - tail.length;
    for (var i = 0; i < tail.length; i++) {
      _lineCache[tailStart + i] = tail[i];
    }

    _logSub = widget.session.logStream.listen((line) {
      setState(() {
        _lineCache[_totalLineCount] = line;
        _totalLineCount++;
      });
      if (_autoScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
        });
      }
    });
    _statusSub = widget.session.statusStream.listen((s) {
      setState(() => _status = s);
    });
  }

  void _requestChunkLoad(int lineIndex) {
    if (_loadingChunk) return;
    _loadingChunk = true;

    final chunkStart = (lineIndex ~/ _chunkSize) * _chunkSize;
    final chunkEnd = (chunkStart + _chunkSize).clamp(0, _totalLineCount);

    widget.session
        .readLineRange(chunkStart, chunkEnd)
        .then((lines) {
          if (!mounted) return;
          setState(() {
            for (var i = 0; i < lines.length; i++) {
              _lineCache[chunkStart + i] = lines[i];
            }
            _loadingChunk = false;
          });
          _evictDistantCache(lineIndex);
        })
        .catchError((e) {
          _loadingChunk = false;
        });
  }

  void _evictDistantCache(int currentIndex) {
    if (_lineCache.length < 2000) return;
    final keysToRemove = _lineCache.keys
        .where((k) => (k - currentIndex).abs() > 1000)
        .toList();
    for (final k in keysToRemove) {
      _lineCache.remove(k);
    }
  }

  Future<void> _toggleSelectionMode() async {
    if (_selectionMode) {
      _exitSelectionMode();
      return;
    }

    setState(() {
      _selectionMode = true;
      _autoScroll = false;
      _loadingSelectableText = true;
      _selectableRangeLabel = null;
    });

    final range = _selectionRange();
    final lines = await widget.session.readLineRange(range.start, range.end);
    if (!mounted) return;

    setState(() {
      _selectableLogText = lines.join('\n');
      if (_selectableLogText!.isNotEmpty) {
        _selectableLogText = '$_selectableLogText\n';
      }
      _selectableRangeLabel =
          '${range.start + 1}-${range.end} / $_totalLineCount 行';
      _loadingSelectableText = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _selectableFocusNode.requestFocus();
      }
    });
  }

  void _exitSelectionMode() {
    if (!_selectionMode) return;
    setState(() => _selectionMode = false);
  }

  ({int start, int end}) _selectionRange() {
    if (_totalLineCount <= 0) {
      return (start: 0, end: 0);
    }

    final position = _scrollController.hasClients
        ? _scrollController.position
        : null;
    final viewportLines = position == null
        ? 60
        : (position.viewportDimension / _lineExtent).ceil();
    final firstVisibleLine = position == null
        ? (_totalLineCount - viewportLines).clamp(0, _totalLineCount)
        : _displayOffset + (position.pixels / _lineExtent).floor();
    final isAtBottom =
        position != null && position.pixels >= position.maxScrollExtent - 2;

    if (isAtBottom) {
      return (
        start: (_totalLineCount - _selectionContextLines * 2).clamp(
          0,
          _totalLineCount,
        ),
        end: _totalLineCount,
      );
    }

    final start = (firstVisibleLine - _selectionContextLines).clamp(
      0,
      _totalLineCount,
    );
    final end = (firstVisibleLine + viewportLines + _selectionContextLines)
        .clamp(start, _totalLineCount);
    return (start: start, end: end);
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _statusSub?.cancel();
    _scrollController.dispose();
    _selectableVerticalController.dispose();
    _selectableHorizontalController.dispose();
    _logSearchController.dispose();
    _selectableFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredIndexes = _hasLogFilter ? _filteredLineIndexes : null;
    return Column(
      children: [
        _buildToolbar(filteredIndexes?.length),
        Expanded(
          child: Container(
            color: const Color(0xFF1E1E1E),
            child: _selectionMode
                ? _buildSelectableLog()
                : _hasLogFilter
                ? _buildFilteredLog(filteredIndexes ?? const [])
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: _visibleCount,
                    itemExtent: _lineExtent,
                    itemBuilder: (ctx, i) {
                      final actualIndex = i + _displayOffset;
                      final line = _lineCache[actualIndex];
                      if (line == null) {
                        _requestChunkLoad(actualIndex);
                        return const SizedBox.shrink();
                      }
                      return _logLine(line);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(int? filteredCount) {
    final theme = Theme.of(context);
    final lineLabel = _selectionMode && _selectableRangeLabel != null
        ? '选择范围 $_selectableRangeLabel'
        : _hasLogFilter
        ? '$filteredCount / $_visibleCount 行'
        : '$_visibleCount 行';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _statusBadge(),
            _metaChip(
              Icons.dns_outlined,
              '${widget.session.host}:${widget.session.port}',
            ),
            _metaChip(Icons.article_outlined, widget.session.logPath),
            SizedBox(
              width: 260,
              child: TextField(
                controller: _logSearchController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _logSearchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: '清空搜索',
                          onPressed: () {
                            _logSearchController.clear();
                            setState(() {});
                          },
                        ),
                  hintText: '过滤日志内容...',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() => _autoScroll = false),
              ),
            ),
            FilterChip(
              selected: _showErrorsOnly,
              avatar: const Icon(Icons.error_outline, size: 16),
              label: const Text('错误'),
              visualDensity: VisualDensity.compact,
              onSelected: (value) => setState(() {
                _showErrorsOnly = value;
                if (value) _showWarningsOnly = false;
                _autoScroll = false;
              }),
            ),
            FilterChip(
              selected: _showWarningsOnly,
              avatar: const Icon(Icons.warning_amber, size: 16),
              label: const Text('警告'),
              visualDensity: VisualDensity.compact,
              onSelected: (value) => setState(() {
                _showWarningsOnly = value;
                if (value) _showErrorsOnly = false;
                _autoScroll = false;
              }),
            ),
            Text(
              lineLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            IconButton(
              icon: Icon(
                _autoScroll ? Icons.vertical_align_bottom : Icons.pause,
                size: 18,
              ),
              tooltip: _autoScroll ? '自动滚动: 开' : '自动滚动: 关',
              onPressed: () => setState(() => _autoScroll = !_autoScroll),
            ),
            IconButton(
              icon: Icon(
                _selectionMode ? Icons.format_clear : Icons.text_fields,
                size: 18,
              ),
              tooltip: _selectionMode ? '退出选择' : '选择复制片段',
              onPressed: _toggleSelectionMode,
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: '复制全部',
              onPressed: _copyAll,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: '清空显示',
              onPressed: _clearVisibleLog,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilteredLog(List<int> indexes) {
    if (indexes.isEmpty) {
      return Center(
        child: Text('没有匹配的日志', style: TextStyle(color: Colors.grey.shade400)),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      itemCount: indexes.length,
      itemExtent: _lineExtent,
      itemBuilder: (ctx, i) => _logLine(_lineCache[indexes[i]] ?? ''),
    );
  }

  Widget _logLine(String line) {
    final query = _logSearchController.text.trim();
    return Container(
      color:
          query.isNotEmpty && line.toLowerCase().contains(query.toLowerCase())
          ? Colors.yellow.withValues(alpha: 0.16)
          : null,
      child: Text(
        line,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'Sarasa Mono SC',
          fontSize: 12,
          color: _lineColor(line),
          height: 1.4,
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String label) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Chip(
        avatar: Icon(icon, size: 16),
        label: Text(label, overflow: TextOverflow.ellipsis),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Color _lineColor(String line) {
    if (_isErrorLine(line)) return Colors.red.shade300;
    if (_isWarnLine(line)) return Colors.orange.shade300;
    return Colors.green.shade200;
  }

  bool _lineMatchesFilters(String line) {
    if (_showErrorsOnly && !_isErrorLine(line)) return false;
    if (_showWarningsOnly && !_isWarnLine(line)) return false;
    final query = _logSearchController.text.trim().toLowerCase();
    return query.isEmpty || line.toLowerCase().contains(query);
  }

  bool _isErrorLine(String line) {
    final upper = line.toUpperCase();
    return upper.contains('ERROR') ||
        upper.contains('STDERR') ||
        line.contains('异常') ||
        line.contains('失败');
  }

  bool _isWarnLine(String line) {
    final upper = line.toUpperCase();
    return upper.contains('WARN') || line.contains('警告');
  }

  Future<void> _copyAll() async {
    final messenger = ScaffoldMessenger.of(context);
    final text = await widget.session.readAllText();
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
  }

  void _clearVisibleLog() {
    setState(() {
      _displayOffset = _totalLineCount;
      _lineCache.clear();
      _logSearchController.clear();
      _showErrorsOnly = false;
      _showWarningsOnly = false;
      if (_selectionMode) {
        _selectableLogText = '';
      }
    });
  }

  Widget _buildSelectableLog() {
    if (_loadingSelectableText) {
      return const Center(child: CircularProgressIndicator());
    }

    return KeyboardListener(
      focusNode: _selectableFocusNode,
      onKeyEvent: (event) {
        if (event is! KeyDownEvent) return;
        final isCopyShortcut =
            event.logicalKey == LogicalKeyboardKey.keyC &&
            (HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed);
        if (isCopyShortcut) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _exitSelectionMode();
            }
          });
        }
      },
      child: Scrollbar(
        controller: _selectableVerticalController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _selectableVerticalController,
          padding: const EdgeInsets.all(8),
          child: Scrollbar(
            controller: _selectableHorizontalController,
            thumbVisibility: true,
            notificationPredicate: (notification) => notification.depth == 1,
            child: SingleChildScrollView(
              controller: _selectableHorizontalController,
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                _selectableLogText ?? '',
                contextMenuBuilder: (context, editableTextState) {
                  final buttonItems = editableTextState.contextMenuButtonItems
                      .map((item) {
                        if (item.type != ContextMenuButtonType.copy) {
                          return item;
                        }

                        return ContextMenuButtonItem(
                          type: item.type,
                          label: item.label,
                          onPressed: () {
                            item.onPressed?.call();
                            _exitSelectionMode();
                          },
                        );
                      })
                      .toList();

                  return AdaptiveTextSelectionToolbar.buttonItems(
                    anchors: editableTextState.contextMenuAnchors,
                    buttonItems: buttonItems,
                  );
                },
                style: TextStyle(
                  fontFamily: 'Sarasa Mono SC',
                  fontSize: 12,
                  color: Colors.green.shade200,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusBadge() {
    Color color;
    String text;
    switch (_status) {
      case SshSessionStatus.connecting:
        color = Colors.orange;
        text = '连接中...';
      case SshSessionStatus.connected:
        color = Colors.green;
        text = '已连接';
      case SshSessionStatus.disconnected:
        color = Colors.grey;
        text = '已断开';
      case SshSessionStatus.error:
        color = Colors.red;
        text = '连接错误';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
