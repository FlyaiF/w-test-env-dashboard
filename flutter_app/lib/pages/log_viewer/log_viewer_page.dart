import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/config_service.dart';
import '../../models/env_info.dart';
import '../../services/env_service.dart';
import '../../services/ssh_service.dart';

/// Parse E_WEBSERVERADDR format: "server_addr&username/password"
/// Returns (host, port, username, password)
({String host, int port, String? username, String? password}) parseServerAddr(
  String addr,
) {
  String serverPart = addr;
  String? username;
  String? password;

  // Split by '&' to get server and credentials
  final ampIdx = addr.indexOf('&');
  if (ampIdx != -1) {
    serverPart = addr.substring(0, ampIdx);
    final credPart = addr.substring(ampIdx + 1);
    final slashIdx = credPart.indexOf('/');
    if (slashIdx != -1) {
      username = credPart.substring(0, slashIdx);
      password = credPart.substring(slashIdx + 1);
    } else {
      username = credPart;
    }
  }

  // Parse host:port
  final parts = serverPart.split(':');
  final host = parts[0];
  final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 22 : 22;

  return (host: host, port: port, username: username, password: password);
}

class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => LogViewerPageState();
}

class LogViewerPageState extends State<LogViewerPage>
    with TickerProviderStateMixin {
  final List<_LogTab> _tabs = [];
  TabController? _tabController;

  void _addTab(EnvInfo env, String username, String password) {
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
      _tabController?.dispose();
      _tabController = TabController(
        length: _tabs.length,
        vsync: this,
        initialIndex: _tabs.length - 1,
      );
    });

    session.connect(username: username, password: password).catchError((e) {
      // Error is handled via the stream
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
      _tabController?.dispose();
      if (_tabs.isNotEmpty) {
        _tabController = TabController(
          length: _tabs.length,
          vsync: this,
          initialIndex: index.clamp(0, _tabs.length - 1),
        );
      } else {
        _tabController = null;
      }
    });
  }

  void _showConnectDialog() async {
    final envService = context.read<EnvService>();
    final config = await ConfigService.load();

    if (!mounted) return;

    final envs = envService.envs
        .where((e) => e.eWebserveraddr != null && e.eWeblogpath != null)
        .toList();

    if (envs.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有配置了Web服务地址和日志路径的环境')));
      return;
    }

    EnvInfo? selectedEnv = envs.first;
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();

    // Pre-fill credentials from the selected env's server addr
    void fillCredentials(EnvInfo? env) {
      if (env?.eWebserveraddr != null) {
        final parsed = parseServerAddr(env!.eWebserveraddr!);
        usernameCtrl.text = parsed.username ?? config.ssh.defaultUsername;
        passwordCtrl.text = parsed.password ?? config.ssh.defaultPassword;
      } else {
        usernameCtrl.text = config.ssh.defaultUsername;
        passwordCtrl.text = config.ssh.defaultPassword;
      }
    }

    fillCredentials(selectedEnv);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final displayAddr = selectedEnv?.eWebserveraddr != null
              ? '${parseServerAddr(selectedEnv!.eWebserveraddr!).host}:${parseServerAddr(selectedEnv!.eWebserveraddr!).port}'
              : '-';
          return AlertDialog(
            title: const Text('SSH连接'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<EnvInfo>(
                    initialValue: selectedEnv,
                    decoration: const InputDecoration(
                      labelText: '选择环境',
                      border: OutlineInputBorder(),
                    ),
                    isExpanded: true,
                    items: envs.map((e) {
                      final p = parseServerAddr(e.eWebserveraddr!);
                      return DropdownMenuItem(
                        value: e,
                        child: Text(
                          '${e.eName ?? "#${e.eNo}"} (${p.host}:${p.port})',
                        ),
                      );
                    }).toList(),
                    onChanged: (v) {
                      setDialogState(() {
                        selectedEnv = v;
                        fillCredentials(v);
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '服务器: $displayAddr',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  Text(
                    '日志路径: ${selectedEnv?.eWeblogpath ?? "-"}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
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
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('连接'),
              ),
            ],
          );
        },
      ),
    );

    if (result == true && selectedEnv != null) {
      _addTab(selectedEnv!, usernameCtrl.text, passwordCtrl.text);
    }

    usernameCtrl.dispose();
    passwordCtrl.dispose();
  }

  @override
  void dispose() {
    for (final tab in _tabs) {
      tab.session.disconnect();
    }
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              Text('日志查看', style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              FilledButton.icon(
                onPressed: _showConnectDialog,
                icon: const Icon(Icons.add),
                label: const Text('新建连接'),
              ),
            ],
          ),
        ),
        if (_tabs.isEmpty)
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.terminal, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('点击"新建连接"开始查看日志', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          )
        else ...[
          // Tab bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabs: _tabs.asMap().entries.map((entry) {
                final i = entry.key;
                final tab = entry.value;
                return Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(tab.name),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () => _closeTab(i),
                        child: const Icon(Icons.close, size: 16),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _tabs
                  .map((tab) => _LogPanel(session: tab.session))
                  .toList(),
            ),
          ),
        ],
      ],
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
  const _LogPanel({required this.session});

  @override
  State<_LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<_LogPanel> {
  final ScrollController _scrollController = ScrollController();
  int _totalLineCount = 0;
  final Map<int, String> _lineCache = {};
  int _displayOffset = 0;
  bool _loadingChunk = false;
  bool _autoScroll = true;
  StreamSubscription? _logSub;
  StreamSubscription? _statusSub;
  SshSessionStatus _status = SshSessionStatus.connecting;

  static const int _chunkSize = 200;

  int get _visibleCount => _totalLineCount - _displayOffset;

  @override
  void initState() {
    super.initState();
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

  @override
  void dispose() {
    _logSub?.cancel();
    _statusSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          color: Colors.grey.shade100,
          child: Row(
            children: [
              _statusBadge(),
              const SizedBox(width: 8),
              Text(
                '${widget.session.host}:${widget.session.port}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(width: 8),
              Text(
                widget.session.logPath,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const Spacer(),
              Text(
                '$_visibleCount 行',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  _autoScroll ? Icons.vertical_align_bottom : Icons.pause,
                  size: 18,
                ),
                tooltip: _autoScroll ? '自动滚动: 开' : '自动滚动: 关',
                onPressed: () => setState(() => _autoScroll = !_autoScroll),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: '复制全部',
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final text = await widget.session.readAllText();
                  await Clipboard.setData(ClipboardData(text: text));
                  messenger.showSnackBar(
                    const SnackBar(content: Text('已复制到剪贴板')),
                  );
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: '清空',
                onPressed: () => setState(() {
                  _displayOffset = _totalLineCount;
                  _lineCache.clear();
                }),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
        // Log content
        Expanded(
          child: Container(
            color: const Color(0xFF1E1E1E),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8),
              itemCount: _visibleCount,
              itemExtent: 16.8,
              itemBuilder: (ctx, i) {
                final actualIndex = i + _displayOffset;
                final line = _lineCache[actualIndex];
                if (line == null) {
                  _requestChunkLoad(actualIndex);
                  return const SizedBox.shrink();
                }
                final isError =
                    line.contains('ERROR') || line.contains('STDERR');
                final isWarn = line.contains('WARN');
                return Text(
                  line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Sarasa Mono SC',
                    fontSize: 12,
                    color: isError
                        ? Colors.red.shade300
                        : isWarn
                        ? Colors.orange.shade300
                        : Colors.green.shade200,
                    height: 1.4,
                  ),
                );
              },
            ),
          ),
        ),
      ],
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
