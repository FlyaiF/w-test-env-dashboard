import 'package:flutter/material.dart';

import '../../api/dto/component_links_input.dart';
import '../../catalog/environment_view.dart';
import '../../inventory/inventory_view.dart';

/// Edit a Component's Resource Inventory references as one full replacement:
/// zero-or-one Server and zero-or-many Databases.
Future<bool> showComponentLinksEditor(
  BuildContext context, {
  required ComponentView component,
  required List<ServerView> servers,
  required List<DatabaseView> databases,
  required Future<String?> Function(ComponentLinksInput input) onSave,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (_) => _ComponentLinksDialog(
          component: component,
          servers: servers,
          databases: databases,
          onSave: onSave,
        ),
      ) ??
      false;
}

class _ComponentLinksDialog extends StatefulWidget {
  final ComponentView component;
  final List<ServerView> servers;
  final List<DatabaseView> databases;
  final Future<String?> Function(ComponentLinksInput input) onSave;

  const _ComponentLinksDialog({
    required this.component,
    required this.servers,
    required this.databases,
    required this.onSave,
  });

  @override
  State<_ComponentLinksDialog> createState() => _ComponentLinksDialogState();
}

class _ComponentLinksDialogState extends State<_ComponentLinksDialog> {
  late int? _serverId;
  late Set<int> _databaseIds;
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

    return AlertDialog(
      title: Text('关联资源 · ${widget.component.roleLabel}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              DropdownButtonFormField<int?>(
                key: const ValueKey('component-links-server'),
                initialValue: _serverId,
                decoration: const InputDecoration(labelText: '运行服务器'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('未关联')),
                  for (final server in widget.servers)
                    DropdownMenuItem<int?>(
                      value: server.id,
                      child: Text(server.displayLabel),
                    ),
                  if (unresolvedServerId != null)
                    DropdownMenuItem<int?>(
                      value: unresolvedServerId,
                      child: Text('#$unresolvedServerId（资源不存在）'),
                    ),
                ],
                onChanged: (value) => setState(() => _serverId = value),
              ),
              const SizedBox(height: 20),
              Text('使用数据库', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              if (widget.databases.isEmpty && unresolvedDatabaseIds.isEmpty)
                Text(
                  '资源清单中暂无数据库',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              for (final database in widget.databases)
                CheckboxListTile(
                  key: ValueKey('component-links-database-${database.id}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _databaseIds.contains(database.id),
                  title: Text(database.displayLabel),
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
