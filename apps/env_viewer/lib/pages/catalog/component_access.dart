import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/config_store.dart';
import '../../services/access/access_launcher.dart';
import '../../services/db_tools/db_tool.dart';
import '../../services/db_tools/db_tool_registry.dart';
import '../../services/ssh_tools/ssh_tool.dart';
import '../../services/ssh_tools/ssh_tool_registry.dart';

/// One launchable action — a chosen tool pointed at a chosen resource. [run]
/// captures the resource id and tool so the widget only has to call it; the
/// brokered credential is fetched and dropped inside [AccessLauncher].
class LaunchOption {
  /// Already-localized menu/button label (e.g. a tool's display name).
  final String label;

  /// Menu section this option belongs to (e.g. a database's label when a
  /// Component uses several). Null renders flat; consecutive options sharing a
  /// group render under one header.
  final String? group;

  final Future<LaunchResult> Function() run;

  const LaunchOption(this.label, this.run, {this.group});
}

/// Popup entries for a launch menu: options sharing a [LaunchOption.group]
/// render under a small disabled header with a divider between groups; ungrouped
/// options render flat. Values index into [options].
List<PopupMenuEntry<int>> launchMenuEntries(
  BuildContext context,
  List<LaunchOption> options,
) {
  final theme = Theme.of(context);
  final entries = <PopupMenuEntry<int>>[];
  String? currentGroup;
  for (var i = 0; i < options.length; i++) {
    final option = options[i];
    if (option.group != null && option.group != currentGroup) {
      if (entries.isNotEmpty) entries.add(const PopupMenuDivider(height: 8));
      entries.add(
        PopupMenuItem<int>(
          enabled: false,
          height: 30,
          child: Text(
            option.group!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    currentGroup = option.group;
    entries.add(
      PopupMenuItem<int>(
        value: i,
        height: 36,
        child: Padding(
          padding: EdgeInsets.only(left: option.group == null ? 0 : 10),
          child: Text(option.label),
        ),
      ),
    );
  }
  return entries;
}

/// Build the SSH launch options for a Server: one per installed SSH tool. An
/// empty list means no tool is available on this platform — the caller renders
/// a disabled control rather than nothing, so the absence is visible.
List<LaunchOption> sshLaunchOptions(
  AccessLauncher launcher,
  int serverId, {
  List<SshTool>? tools,
  PasswordMode preferredMode = PasswordMode.argv,
  String? startPath,
  Map<String, String>? executablePaths,
  String? preferredToolId,
}) {
  final available = [...(tools ?? SshToolRegistry.availableOnPlatform)];
  // Surface the configured default tool first, preserving the rest of the order.
  if (preferredToolId != null) {
    final idx = available.indexWhere((t) => t.id == preferredToolId);
    if (idx > 0) available.insert(0, available.removeAt(idx));
  }
  return [
    for (final tool in available)
      LaunchOption(
        tool.displayName,
        () => launcher.launchSsh(
          serverId,
          tool,
          preferredMode: preferredMode,
          startPath: startPath,
          executableOverride: executablePaths?[tool.id],
        ),
      ),
  ];
}

/// Build the DB launch options for a Component's Databases: per database, one
/// option per installed DB tool that supports its engine ([DbTool.supportsType],
/// via [databaseTypes]). With several databases the options carry the database
/// label as their menu [LaunchOption.group] so the menu renders sectioned
/// instead of as a flat cross product.
List<LaunchOption> dbLaunchOptions(
  AccessLauncher launcher,
  List<int> databaseIds, {
  List<DbTool>? tools,
  String? connectionName,
  Map<int, String>? databaseLabels,
  Map<int, String?>? databaseTypes,
  Map<String, String>? executablePaths,
}) {
  final available = tools ?? DbToolRegistry.availableOnPlatform;
  final qualify = databaseIds.length > 1;
  return [
    for (final databaseId in databaseIds)
      for (final tool in available)
        if (databaseTypes == null || tool.supportsType(databaseTypes[databaseId]))
          LaunchOption(
            tool.displayName,
            group: qualify
                ? (databaseLabels?[databaseId] ?? '#$databaseId')
                : null,
            () => launcher.launchDb(
              databaseId,
              tool,
              name: connectionName,
              executableOverride: executablePaths?[tool.id],
            ),
          ),
  ];
}

/// Local Desktop Integration surface for a Component (ADR-0005): launch the
/// user's own SSH tool against the Server it runs on, and their own DB tool
/// against each Database it uses. Credentials are brokered on demand by
/// [AccessLauncher] and never persisted here. Renders nothing when the Component
/// references neither a Server nor a Database.
class ComponentAccessBar extends StatelessWidget {
  /// Server this Component runs on, or null when none is linked.
  final int? serverId;

  /// Databases this Component uses (by id); may be empty.
  final List<int> databaseIds;

  /// Resolved short labels (role + host) per database id, used to disambiguate the
  /// launch menu when a Component uses more than one database. Missing ids fall
  /// back to `#id`.
  final Map<int, String>? databaseLabels;

  /// Raw engine type per database id (`ORACLE` | ...), used to keep
  /// engine-specific tools out of the menu for databases they can't open.
  final Map<int, String?>? databaseTypes;

  /// Human label used to name launched connections (e.g. in DBeaver).
  final String? connectionName;

  const ComponentAccessBar({
    super.key,
    required this.serverId,
    required this.databaseIds,
    this.databaseLabels,
    this.databaseTypes,
    this.connectionName,
  });

  @override
  Widget build(BuildContext context) {
    final hasServer = serverId != null;
    final hasDb = databaseIds.isNotEmpty;
    if (!hasServer && !hasDb) return const SizedBox.shrink();

    final launcher = context.read<AccessLauncher>();
    final config = context.watch<ConfigStore>();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (hasServer)
          _LaunchButton(
            icon: Icons.terminal,
            label: 'SSH 连接',
            options: sshLaunchOptions(
              launcher,
              serverId!,
              preferredMode: config.passwordMode,
              executablePaths: config.sshExecutablePaths,
              preferredToolId: config.defaultTerminalToolId,
            ),
            emptyTooltip: '当前平台没有可用的 SSH 工具',
          ),
        if (hasDb)
          _LaunchButton(
            icon: Icons.storage_outlined,
            label: '数据库工具',
            options: dbLaunchOptions(
              launcher,
              databaseIds,
              connectionName: connectionName,
              databaseLabels: databaseLabels,
              databaseTypes: databaseTypes,
              executablePaths: config.dbExecutablePaths,
            ),
            emptyTooltip: '当前平台没有可用的数据库工具',
          ),
      ],
    );
  }
}

/// A launch action with zero, one, or many options. Zero → a disabled control
/// explaining why; one → a direct button; many → a popup menu to choose from.
/// Runs the chosen option, blocks re-entry while in flight, and reports the
/// [LaunchResult] (already localized by the tool) via a SnackBar.
class _LaunchButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final List<LaunchOption> options;
  final String emptyTooltip;

  const _LaunchButton({
    required this.icon,
    required this.label,
    required this.options,
    required this.emptyTooltip,
  });

  @override
  State<_LaunchButton> createState() => _LaunchButtonState();
}

class _LaunchButtonState extends State<_LaunchButton> {
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
      SnackBar(
        content: Text(result.message ?? (result.ok ? '已启动' : '启动失败')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final icon = _busy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(widget.icon, size: 18);

    if (widget.options.isEmpty) {
      return Tooltip(
        message: widget.emptyTooltip,
        child: TextButton.icon(
          onPressed: null,
          icon: Icon(widget.icon, size: 18),
          label: Text(widget.label),
        ),
      );
    }

    if (widget.options.length == 1) {
      final only = widget.options.first;
      return TextButton.icon(
        onPressed: _busy ? null : () => _run(only),
        icon: icon,
        label: Text(widget.label),
      );
    }

    final theme = Theme.of(context);
    return PopupMenuButton<int>(
      enabled: !_busy,
      tooltip: widget.label,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (i) => _run(widget.options[i]),
      itemBuilder: (context) => launchMenuEntries(context, widget.options),
      // Styled to sit beside sibling TextButtons as an equal, not a bare Row.
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: theme.colorScheme.primary),
          child: IconTheme.merge(
            data: IconThemeData(color: theme.colorScheme.primary),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(width: 6),
                Text(widget.label),
                const Icon(Icons.arrow_drop_down, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
