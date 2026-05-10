import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/config_service.dart';
import '../../models/env_info.dart';
import '../../services/env_service.dart';
import '../../services/ssh_tools/ssh_tool.dart';
import '../../services/ssh_tools/ssh_tool_registry.dart';
import '../../utils/addr_parser.dart';
import '../../widgets/filter_history_text_field.dart';

enum _EnvQuickFilter { logConfig, url, recent, incomplete }

class DashboardPage extends StatefulWidget {
  final void Function(EnvInfo env)? onViewLog;

  const DashboardPage({super.key, this.onViewLog});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _searchController = TextEditingController();
  final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');
  final Set<_EnvQuickFilter> _filters = {};
  Timer? _debounce;
  int? _selectedEnvNo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EnvService>().load();
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
    final service = context.watch<EnvService>();
    final envs = _applyQuickFilters(service.filteredEnvs);
    final selected = _selectedEnv(envs);

    return Column(
      children: [
        _buildHeader(service, envs.length),
        if (service.error != null) _buildErrorBanner(service),
        if (service.loading || service.syncing) const LinearProgressIndicator(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 900;
              if (envs.isEmpty && !service.loading) {
                return _buildEmptyState();
              }
              if (compact) {
                return Column(
                  children: [
                    Expanded(child: _buildEnvList(envs, selected)),
                    const Divider(height: 1),
                    SizedBox(height: 280, child: _buildDetailPane(selected)),
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

  Widget _buildHeader(EnvService service, int visibleCount) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('环境工作台', style: theme.textTheme.headlineSmall),
              const SizedBox(width: 12),
              Text(
                '显示 $visibleCount / ${service.total} 条',
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
                  hintText: '搜索编号、名称、地址、日志、版本...',
                  onChanged: (v) {
                    setState(() {});
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), () {
                      service.setSearch(v);
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: service.syncing ? null : service.sync,
                tooltip: '从远程刷新',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterChip(_EnvQuickFilter.logConfig, '可看日志', Icons.article),
              _filterChip(_EnvQuickFilter.url, '有访问地址', Icons.link),
              _filterChip(_EnvQuickFilter.recent, '30天内更新', Icons.schedule),
              _filterChip(
                _EnvQuickFilter.incomplete,
                '缺少配置',
                Icons.warning_amber,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChip(_EnvQuickFilter filter, String label, IconData icon) {
    final selected = _filters.contains(filter);
    return FilterChip(
      selected: selected,
      avatar: Icon(icon, size: 16),
      label: Text(label),
      onSelected: (value) {
        setState(() {
          if (value) {
            _filters.add(filter);
          } else {
            _filters.remove(filter);
          }
        });
      },
    );
  }

  Widget _buildErrorBanner(EnvService service) {
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
              service.error!,
              style: TextStyle(color: colorScheme.error),
            ),
          ),
          TextButton(onPressed: service.load, child: const Text('重试')),
        ],
      ),
    );
  }

  Widget _buildEnvList(List<EnvInfo> envs, EnvInfo? selected) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      itemCount: envs.length,
      itemBuilder: (context, index) {
        final env = envs[index];
        return _EnvListTile(
          env: env,
          selected: selected?.eNo == env.eNo,
          dateFmt: _dateFmt,
          onTap: () => setState(() => _selectedEnvNo = env.eNo),
          onCopyUrl: env.eUrl == null
              ? null
              : () => _copyToClipboard(env.eUrl!, '访问地址'),
          onOpenUrl: env.eUrl == null ? null : () => _launchUrl(env.eUrl!),
          onViewLog: _canViewLog(env)
              ? () => widget.onViewLog?.call(env)
              : null,
        );
      },
    );
  }

  Widget _buildDetailPane(EnvInfo? env) {
    final theme = Theme.of(context);
    if (env == null) {
      return Center(
        child: Text(
          '选择一个环境查看详情',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
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
                    '#${env.eNo}',
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    env.eName ?? '未命名环境',
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: env.eUrl == null
                      ? null
                      : () => _launchUrl(env.eUrl!),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('打开环境'),
                ),
                OutlinedButton.icon(
                  onPressed: env.eSeeurl == null
                      ? null
                      : () => _launchUrl(env.eSeeurl!),
                  icon: const Icon(Icons.travel_explore),
                  label: const Text('打开SEE'),
                ),
                OutlinedButton.icon(
                  onPressed: _canViewLog(env)
                      ? () => widget.onViewLog?.call(env)
                      : null,
                  icon: const Icon(Icons.article),
                  label: const Text('查看日志'),
                ),
                OutlinedButton.icon(
                  onPressed: env.eVersion == null
                      ? null
                      : () => _copyToClipboard(env.eVersion!, '版本号'),
                  icon: const Icon(Icons.copy),
                  label: const Text('复制版本'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _sectionTitle('运行信息'),
            _DetailGrid(
              rows: [
                _DetailItem('访问地址', env.eUrl, copy: _copyToClipboard),
                _DetailItem('版本号', env.eVersion, copy: _copyToClipboard),
                _DetailItem(
                  '更新时间',
                  env.eUpdatetime == null
                      ? null
                      : _dateFmt.format(env.eUpdatetime!.toLocal()),
                ),
                _DetailItem('数据库类型', env.eDbtype),
              ],
            ),
            const SizedBox(height: 18),
            _sectionTitle('数据库'),
            _DetailGrid(
              rows: [
                _DetailItem('业务库', env.eYwdb, copy: _copyToClipboard),
                _DetailItem('中间库', env.eZjdb, copy: _copyToClipboard),
              ],
            ),
            const SizedBox(height: 18),
            _sectionTitle('日志'),
            _DetailGrid(
              rows: [
                _DetailItem(
                  'Web服务地址',
                  env.eWebserveraddr,
                  copy: _copyToClipboard,
                  trailingActions: [
                    _SshLaunchButton(
                      addr: env.eWebserveraddr,
                      kind: SshToolKind.terminal,
                      icon: Icons.terminal,
                      tooltip: '在终端中打开',
                    ),
                    _SshLaunchButton(
                      addr: env.eWebserveraddr,
                      kind: SshToolKind.sftp,
                      icon: Icons.folder_open,
                      tooltip: '在 SFTP 中打开',
                    ),
                  ],
                ),
                _DetailItem('Web日志路径', env.eWeblogpath, copy: _copyToClipboard),
              ],
            ),
            const SizedBox(height: 18),
            _sectionTitle('备注'),
            SelectableText(
              env.eMemo?.isNotEmpty == true ? env.eMemo! : '-',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off, size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            '没有匹配的环境',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  List<EnvInfo> _applyQuickFilters(List<EnvInfo> envs) {
    var result = envs;
    for (final filter in _filters) {
      result = result.where((env) {
        switch (filter) {
          case _EnvQuickFilter.logConfig:
            return _canViewLog(env);
          case _EnvQuickFilter.url:
            return env.eUrl != null;
          case _EnvQuickFilter.recent:
            final updated = env.eUpdatetime;
            if (updated == null) return false;
            return updated.toLocal().isAfter(
              DateTime.now().subtract(const Duration(days: 30)),
            );
          case _EnvQuickFilter.incomplete:
            return env.eUrl == null ||
                env.eVersion == null ||
                env.eWebserveraddr == null ||
                env.eWeblogpath == null;
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

  bool _canViewLog(EnvInfo env) =>
      env.eWeblogpath != null && env.eWebserveraddr != null;

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制$label'),
        duration: const Duration(seconds: 1),
      ),
    );
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
  final EnvInfo env;
  final bool selected;
  final DateFormat dateFmt;
  final VoidCallback onTap;
  final VoidCallback? onCopyUrl;
  final VoidCallback? onOpenUrl;
  final VoidCallback? onViewLog;

  const _EnvListTile({
    required this.env,
    required this.selected,
    required this.dateFmt,
    required this.onTap,
    this.onCopyUrl,
    this.onOpenUrl,
    this.onViewLog,
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
                    '#${env.eNo}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      env.eName ?? '-',
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onViewLog != null)
                    IconButton(
                      icon: const Icon(Icons.article, size: 18),
                      tooltip: '查看日志',
                      onPressed: onViewLog,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                    ),
                  if (onOpenUrl != null)
                    IconButton(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      tooltip: '打开环境',
                      onPressed: onOpenUrl,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _InlineInfo(
                icon: Icons.link,
                text: env.eUrl ?? '未配置访问地址',
                muted: env.eUrl == null,
                trailing: onCopyUrl == null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.copy, size: 14),
                        tooltip: '复制地址',
                        onPressed: onCopyUrl,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                      ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: _InlineInfo(
                      icon: Icons.label_outline,
                      text: env.eVersion ?? '-',
                      muted: env.eVersion == null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 128,
                    child: _InlineInfo(
                      icon: Icons.schedule,
                      text: env.eUpdatetime == null
                          ? '-'
                          : dateFmt.format(env.eUpdatetime!.toLocal()),
                      muted: env.eUpdatetime == null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineInfo extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool muted;
  final Widget? trailing;

  const _InlineInfo({
    required this.icon,
    required this.text,
    this.muted = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final color = muted
        ? Theme.of(context).colorScheme.outline
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: color),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _DetailItem {
  final String label;
  final String? value;
  final void Function(String text, String label)? copy;
  final List<Widget> trailingActions;

  const _DetailItem(
    this.label,
    this.value, {
    this.copy,
    this.trailingActions = const [],
  });
}

class _DetailGrid extends StatelessWidget {
  final List<_DetailItem> rows;

  const _DetailGrid({required this.rows});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 560;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: rows
              .map(
                (item) => SizedBox(
                  width: twoColumns
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth,
                  child: _DetailField(item: item),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _DetailField extends StatelessWidget {
  final _DetailItem item;

  const _DetailField({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = item.value?.isNotEmpty == true ? item.value! : '-';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  value,
                  maxLines: 2,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (item.copy != null && item.value?.isNotEmpty == true)
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: '复制${item.label}',
                  onPressed: () => item.copy!(item.value!, item.label),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                ),
              ...item.trailingActions,
            ],
          ),
        ],
      ),
    );
  }
}

class _SshLaunchButton extends StatelessWidget {
  final String? addr;
  final SshToolKind kind;
  final IconData icon;
  final String tooltip;

  const _SshLaunchButton({
    required this.addr,
    required this.kind,
    required this.icon,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final available = SshToolRegistry.availableFor(kind);
    final hasAddr = addr != null && addr!.trim().isNotEmpty;
    final disabled = !hasAddr || available.isEmpty;
    final disabledReason = !hasAddr
        ? '$tooltip（无地址）'
        : available.isEmpty
        ? '$tooltip（当前平台无可用工具）'
        : tooltip;

    return IconButton(
      icon: Icon(icon, size: 16),
      tooltip: disabledReason,
      onPressed: disabled ? null : () => _onPressed(context),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
    );
  }

  Future<void> _onPressed(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final config = await ConfigService.load();
    final tools = SshToolRegistry.availableFor(kind);
    if (tools.isEmpty) return;

    final defaultId = kind == SshToolKind.terminal
        ? config.sshTools.defaultTerminalToolId
        : config.sshTools.defaultSftpToolId;

    SshTool? tool;
    if (defaultId != null) {
      tool = tools.firstWhere(
        (t) => t.id == defaultId,
        orElse: () => tools.first,
      );
    } else if (tools.length == 1) {
      tool = tools.first;
    } else {
      if (!context.mounted) return;
      tool = await _pickTool(context, tools);
    }
    if (tool == null) return;

    final target = _resolveTarget(addr!, config.ssh);
    if (target == null) {
      messenger.showSnackBar(const SnackBar(content: Text('无法解析地址')));
      return;
    }

    final preferred = _parsePasswordMode(config.sshTools.passwordMode);
    final result = await tool.launch(
      target,
      preferredMode: preferred,
      executableOverride: config.sshTools.executablePaths[tool.id],
    );

    if (result.message != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(result.message!),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<SshTool?> _pickTool(
    BuildContext context,
    List<SshTool> tools,
  ) async {
    return showMenu<SshTool>(
      context: context,
      position: _menuPositionFor(context),
      items: [
        for (final t in tools)
          PopupMenuItem<SshTool>(value: t, child: Text(t.displayName)),
      ],
    );
  }

  RelativeRect _menuPositionFor(BuildContext context) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final box = context.findRenderObject() as RenderBox?;
    if (overlay == null || box == null) {
      return const RelativeRect.fromLTRB(0, 0, 0, 0);
    }
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    return RelativeRect.fromLTRB(
      origin.dx,
      origin.dy + box.size.height,
      origin.dx + box.size.width,
      origin.dy,
    );
  }

  ConnectionTarget? _resolveTarget(String rawAddr, SshConfig defaults) {
    final parsed = parseServerAddr(rawAddr);
    if (parsed.host.isEmpty) return null;
    final user = (parsed.username != null && parsed.username!.isNotEmpty)
        ? parsed.username
        : (defaults.defaultUsername.isNotEmpty
            ? defaults.defaultUsername
            : null);
    final pwd = (parsed.password != null && parsed.password!.isNotEmpty)
        ? parsed.password
        : (defaults.defaultPassword.isNotEmpty
            ? defaults.defaultPassword
            : null);
    return ConnectionTarget(
      host: parsed.host,
      port: parsed.port,
      username: user,
      password: pwd,
    );
  }

  PasswordMode _parsePasswordMode(String mode) {
    switch (mode) {
      case 'clipboard':
        return PasswordMode.clipboard;
      case 'none':
        return PasswordMode.none;
      case 'argv':
      default:
        return PasswordMode.argv;
    }
  }
}
