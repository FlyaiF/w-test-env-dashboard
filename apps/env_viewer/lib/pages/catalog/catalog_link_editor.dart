import 'dart:math';

import 'package:flutter/material.dart';

import '../../api/dto/component_links_input.dart';
import '../../catalog/environment_view.dart';
import '../../inventory/inventory_view.dart';

/// Edit a Component's Resource Inventory references as one full replacement:
/// zero-or-one Server and zero-or-many Databases.
///
/// [serverUsage] / [databaseUsage] map resource IDs to the names of the
/// Environments already referencing them, so same-address resources can be
/// told apart.
Future<bool> showComponentLinksEditor(
  BuildContext context, {
  required ComponentView component,
  required List<ServerView> servers,
  required List<DatabaseView> databases,
  Map<int, List<String>> serverUsage = const {},
  Map<int, List<String>> databaseUsage = const {},
  required Future<String?> Function(ComponentLinksInput input) onSave,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (_) => _ComponentLinksDialog(
          component: component,
          servers: servers,
          databases: databases,
          serverUsage: serverUsage,
          databaseUsage: databaseUsage,
          onSave: onSave,
        ),
      ) ??
      false;
}

class _ComponentLinksDialog extends StatefulWidget {
  final ComponentView component;
  final List<ServerView> servers;
  final List<DatabaseView> databases;
  final Map<int, List<String>> serverUsage;
  final Map<int, List<String>> databaseUsage;
  final Future<String?> Function(ComponentLinksInput input) onSave;

  const _ComponentLinksDialog({
    required this.component,
    required this.servers,
    required this.databases,
    required this.serverUsage,
    required this.databaseUsage,
    required this.onSave,
  });

  @override
  State<_ComponentLinksDialog> createState() => _ComponentLinksDialogState();
}

class _ComponentLinksDialogState extends State<_ComponentLinksDialog> {
  /// RadioGroup needs a non-null value for the explicit 未关联 choice.
  static const int _noServer = -1;

  late int? _serverId;
  late Set<int> _databaseIds;
  String _query = '';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _serverId = widget.component.serverId;
    _databaseIds = widget.component.databaseIds.toSet();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onSave(
      ComponentLinksInput(
        serverId: _serverId,
        databaseIds: _databaseIds.toList(growable: false),
      ),
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _error = error;
    });
  }

  String? _usageText(Map<int, List<String>> usage, int id) {
    final names = usage[id];
    if (names == null || names.isEmpty) return null;
    return '用于：${names.join('、')}';
  }

  Widget? _usageSubtitle(Map<int, List<String>> usage, int id) {
    final text = _usageText(usage, id);
    return text == null ? null : Text(text);
  }

  /// Title enriched with the SSH login (`user@host`) so one host registered
  /// under different accounts is distinguishable.
  String _serverTitle(ServerView server) {
    final username = server.sshUsername;
    if (username == null) return server.displayLabel;
    return '$username@${server.displayLabel}';
  }

  /// Title enriched with the login user (`user@host:port/service`) so
  /// same-address Databases are distinguishable.
  String _databaseTitle(DatabaseView database) {
    final username = database.username;
    final address = database.address;
    final target = username == null
        ? address
        : (address.isEmpty ? username : '$username@$address');
    final parts = [
      database.roleLabel,
      database.typeLabel,
      target,
    ].where((part) => part.isNotEmpty).toList(growable: false);
    return parts.isEmpty ? '#${database.id}' : parts.join(' · ');
  }

  bool _matchesQuery(Iterable<String?> haystack) {
    if (_query.isEmpty) return true;
    return haystack.any(
      (text) => text != null && text.toLowerCase().contains(_query),
    );
  }

  bool _serverVisible(ServerView server) {
    if (_serverId == server.id) return true;
    return _matchesQuery([
      _serverTitle(server),
      _usageText(widget.serverUsage, server.id),
    ]);
  }

  bool _databaseVisible(DatabaseView database) {
    if (_databaseIds.contains(database.id)) return true;
    return _matchesQuery([
      _databaseTitle(database),
      _usageText(widget.databaseUsage, database.id),
    ]);
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }

  Widget _emptyHint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.outline),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final serverIds = widget.servers.map((server) => server.id).toSet();
    final unresolvedServerId =
        _serverId != null && !serverIds.contains(_serverId) ? _serverId : null;
    final databaseById = {
      for (final database in widget.databases) database.id: database,
    };
    final unresolvedDatabaseIds =
        _databaseIds
            .where((id) => !databaseById.containsKey(id))
            .toList(growable: false)
          ..sort();

    final visibleServers = widget.servers
        .where(_serverVisible)
        .toList(growable: false);
    final visibleDatabases = widget.databases
        .where(_databaseVisible)
        .toList(growable: false);

    final maxHeight = min(560.0, MediaQuery.sizeOf(context).height - 180);

    return AlertDialog(
      title: Text('关联资源 · ${widget.component.roleLabel}'),
      content: SizedBox(
        width: 560,
        height: maxHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[
              Container(
                key: const ValueKey('component-links-error'),
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              key: const ValueKey('component-links-search'),
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: '搜索主机、库名、账号或环境…',
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
            _sectionTitle('运行服务器'),
            Expanded(
              flex: 2,
              child: RadioGroup<int>(
                groupValue: _serverId ?? _noServer,
                onChanged: (value) => setState(
                  () => _serverId = value == null || value == _noServer
                      ? null
                      : value,
                ),
                child: ListView(
                  children: [
                    RadioListTile<int>(
                      key: const ValueKey('component-links-server-none'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: _noServer,
                      title: const Text('未关联'),
                    ),
                    if (visibleServers.isEmpty && widget.servers.isNotEmpty)
                      _emptyHint('无匹配服务器'),
                    for (final server in visibleServers)
                      RadioListTile<int>(
                        key: ValueKey('component-links-server-${server.id}'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: server.id,
                        title: Text(_serverTitle(server)),
                        subtitle: _usageSubtitle(widget.serverUsage, server.id),
                      ),
                    if (unresolvedServerId != null)
                      RadioListTile<int>(
                        key: const ValueKey('component-links-server-missing'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: unresolvedServerId,
                        title: Text('#$unresolvedServerId（资源不存在）'),
                      ),
                  ],
                ),
              ),
            ),
            _sectionTitle('使用数据库'),
            Expanded(
              flex: 3,
              child: ListView(
                children: [
                  if (widget.databases.isEmpty &&
                      unresolvedDatabaseIds.isEmpty)
                    _emptyHint('资源清单中暂无数据库')
                  else if (visibleDatabases.isEmpty &&
                      unresolvedDatabaseIds.isEmpty)
                    _emptyHint('无匹配数据库'),
                  for (final database in visibleDatabases)
                    CheckboxListTile(
                      key: ValueKey('component-links-database-${database.id}'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: _databaseIds.contains(database.id),
                      title: Text(_databaseTitle(database)),
                      subtitle: _usageSubtitle(
                        widget.databaseUsage,
                        database.id,
                      ),
                      onChanged: (selected) {
                        setState(() {
                          if (selected ?? false) {
                            _databaseIds.add(database.id);
                          } else {
                            _databaseIds.remove(database.id);
                          }
                        });
                      },
                    ),
                  for (final id in unresolvedDatabaseIds)
                    CheckboxListTile(
                      key: ValueKey('component-links-database-$id'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: true,
                      title: Text('#$id（资源不存在）'),
                      onChanged: (selected) {
                        if (selected == false) {
                          setState(() => _databaseIds.remove(id));
                        }
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('component-links-save'),
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }
}
