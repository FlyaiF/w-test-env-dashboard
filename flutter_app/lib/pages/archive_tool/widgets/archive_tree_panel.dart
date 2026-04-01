import 'package:flutter/material.dart';

import '../../../src/rust/api/zipr_api.dart';
import '../archive_tree_builder.dart';

class ArchiveTreePanel extends StatefulWidget {
  final List<ArchiveEntry> entries;
  final ValueChanged<ArchiveEntry>? onEntrySelected;
  final ValueChanged<String>? onExtract;
  final ValueChanged<String>? onReplace;
  final ValueChanged<String>? onDelete;

  const ArchiveTreePanel({
    super.key,
    required this.entries,
    this.onEntrySelected,
    this.onExtract,
    this.onReplace,
    this.onDelete,
  });

  @override
  State<ArchiveTreePanel> createState() => _ArchiveTreePanelState();
}

class _ArchiveTreePanelState extends State<ArchiveTreePanel> {
  late List<TreeNode> _tree;
  final Set<String> _expanded = {};
  String? _selectedExpr;
  final TextEditingController _filterController = TextEditingController();
  String _filterText = '';
  final Set<String> _filterCollapsed = {};
  Set<String> _effectiveExpanded = {};

  @override
  void initState() {
    super.initState();
    _tree = buildTree(widget.entries);
    _filterController.addListener(() {
      final newFilter = _filterController.text.toLowerCase();
      if (newFilter != _filterText) {
        setState(() {
          _filterText = newFilter;
          _filterCollapsed.clear();
        });
      }
    });
  }

  @override
  void didUpdateWidget(ArchiveTreePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.entries != oldWidget.entries) {
      _tree = buildTree(widget.entries);
      _filterController.clear();
    }
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  List<TreeNode> _filterNodes(
    List<TreeNode> nodes,
    String filter,
    Set<String> autoExpand,
  ) {
    final result = <TreeNode>[];
    for (final node in nodes) {
      final nameMatches = node.name.toLowerCase().contains(filter);
      final filteredChildren = _filterNodes(node.children, filter, autoExpand);
      if (nameMatches || filteredChildren.isNotEmpty) {
        result.add(TreeNode(
          name: node.name,
          fullExpr: node.fullExpr,
          isArchive: node.isArchive,
          children: nameMatches ? node.children : filteredChildren,
          entry: node.entry,
        ));
        if (filteredChildren.isNotEmpty) {
          autoExpand.add(node.fullExpr);
        }
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    List<TreeNode> displayTree;
    Set<String> effectiveExpanded;

    if (_filterText.isEmpty) {
      displayTree = _tree;
      effectiveExpanded = _expanded;
    } else {
      final autoExpand = <String>{};
      displayTree = _filterNodes(_tree, _filterText, autoExpand);
      effectiveExpanded = {
        ..._expanded,
        ...autoExpand,
      }..removeAll(_filterCollapsed);
    }

    _effectiveExpanded = effectiveExpanded;
    final flatNodes = <_FlatNode>[];
    _flattenWith(displayTree, 0, flatNodes, effectiveExpanded);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _filterController,
            decoration: InputDecoration(
              hintText: '搜索文件...',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _filterText.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => _filterController.clear(),
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: flatNodes.length,
            itemBuilder: (context, index) => _buildRow(flatNodes[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildRow(_FlatNode flat) {
    final node = flat.node;
    final hasChildren = node.children.isNotEmpty;
    final isExpanded = _effectiveExpanded.contains(node.fullExpr);
    final isSelected = _selectedExpr == node.fullExpr;

    return GestureDetector(
      onSecondaryTapUp: (details) {
        _showContextMenu(context, details.globalPosition, node);
      },
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedExpr = node.fullExpr;
            if (hasChildren) {
              if (isExpanded) {
                _expanded.remove(node.fullExpr);
                if (_filterText.isNotEmpty) {
                  _filterCollapsed.add(node.fullExpr);
                }
              } else {
                _expanded.add(node.fullExpr);
                _filterCollapsed.remove(node.fullExpr);
              }
            }
          });
          if (node.entry != null) {
            widget.onEntrySelected?.call(node.entry!);
          }
        },
        child: Container(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          padding: EdgeInsets.only(
            left: 16.0 + flat.depth * 20.0,
            top: 4,
            bottom: 4,
            right: 8,
          ),
          child: Row(
            children: [
              if (hasChildren)
                Icon(
                  isExpanded ? Icons.expand_more : Icons.chevron_right,
                  size: 18,
                )
              else
                const SizedBox(width: 18),
              const SizedBox(width: 4),
              Icon(_iconForNode(node), size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  node.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (node.entry != null)
                Text(
                  _formatSize(node.entry!.size.toInt()),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showContextMenu(
      BuildContext context, Offset position, TreeNode node) {
    // Use the original entry expr (full path) for operations
    final expr = node.entry?.expr ?? node.fullExpr;
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        if (node.entry != null)
          PopupMenuItem(
            child: const Row(
              children: [
                Icon(Icons.file_download, size: 18),
                SizedBox(width: 8),
                Text('提取'),
              ],
            ),
            onTap: () => widget.onExtract?.call(expr),
          ),
        if (node.entry != null)
          PopupMenuItem(
            child: const Row(
              children: [
                Icon(Icons.swap_horiz, size: 18),
                SizedBox(width: 8),
                Text('替换'),
              ],
            ),
            onTap: () => widget.onReplace?.call(expr),
          ),
        if (node.entry != null)
          PopupMenuItem(
            child: const Row(
              children: [
                Icon(Icons.delete_outline, size: 18),
                SizedBox(width: 8),
                Text('删除'),
              ],
            ),
            onTap: () => widget.onDelete?.call(expr),
          ),
      ],
    );
  }

  IconData _iconForNode(TreeNode node) {
    if (node.isArchive) return Icons.inventory_2;
    if (node.children.isNotEmpty) return Icons.folder_outlined;
    final lower = node.name.toLowerCase();
    if (lower.endsWith('.class')) return Icons.code;
    if (lower.endsWith('.xml') || lower.endsWith('.properties')) {
      return Icons.settings;
    }
    return Icons.insert_drive_file_outlined;
  }

  void _flattenWith(
    List<TreeNode> nodes,
    int depth,
    List<_FlatNode> out,
    Set<String> expanded,
  ) {
    for (final node in nodes) {
      out.add(_FlatNode(node: node, depth: depth));
      if (expanded.contains(node.fullExpr) && node.children.isNotEmpty) {
        _flattenWith(node.children, depth + 1, out, expanded);
      }
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _FlatNode {
  final TreeNode node;
  final int depth;
  _FlatNode({required this.node, required this.depth});
}
