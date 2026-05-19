import 'package:flutter/material.dart';

import '../../../src/rust/api/zipr_api.dart';
import 'package:shared_ui/shared_ui.dart';
import '../archive_tree_builder.dart';

class ArchiveTreePanel extends StatefulWidget {
  final List<ArchiveEntry> entries;
  final ValueChanged<ArchiveEntry>? onEntrySelected;
  final ValueChanged<String>? onExtract;
  final ValueChanged<String>? onReplace;
  final ValueChanged<String>? onDelete;
  /// Invoked when the user opens a lazy nested-archive node and its
  /// children haven't been loaded yet. The provided `zipExpr` is the
  /// nested archive's full expression (e.g. `app.war!/inner.jar`).
  final ValueChanged<String>? onExpandArchive;
  /// Zip expressions currently being expanded (loading spinner shown).
  final Set<String> expandingArchives;

  const ArchiveTreePanel({
    super.key,
    required this.entries,
    this.onEntrySelected,
    this.onExtract,
    this.onReplace,
    this.onDelete,
    this.onExpandArchive,
    this.expandingArchives = const {},
  });

  @override
  State<ArchiveTreePanel> createState() => _ArchiveTreePanelState();
}

class _ArchiveTreePanelState extends State<ArchiveTreePanel> {
  List<TreeNode> _tree = const [];
  bool _buildingTree = false;
  final Set<String> _expanded = {};
  String? _selectedExpr;
  final TextEditingController _filterController = TextEditingController();
  String _filterText = '';
  final Set<String> _filterCollapsed = {};
  Set<String> _effectiveExpanded = {};

  // Memo cache for flatten output. Invalidated when state affecting the
  // visible tree changes; reused across parent rebuilds.
  List<_FlatNode>? _flatCache;
  List<TreeNode>? _flatCacheTreeRef;
  String? _flatCacheFilter;
  int _expandedVersion = 0;
  int? _flatCacheExpandedVersion;

  @override
  void initState() {
    super.initState();
    _scheduleInitialBuild(widget.entries);
    _filterController.addListener(() {
      final newFilter = _filterController.text.toLowerCase();
      if (newFilter != _filterText) {
        setState(() {
          _filterText = newFilter;
          _filterCollapsed.clear();
          _flatCache = null;
        });
      }
    });
  }

  void _scheduleInitialBuild(List<ArchiveEntry> entries) {
    // For small archives, build synchronously to avoid a flash of empty UI.
    if (entries.length < 2000) {
      _tree = buildTree(entries);
      return;
    }
    _buildingTree = true;
    // Yield once so the spinner can paint, then run the heavy build.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(Duration.zero);
      final tree = buildTree(entries);
      if (!mounted) return;
      setState(() {
        _tree = tree;
        _buildingTree = false;
        _flatCache = null;
      });
    });
  }

  @override
  void didUpdateWidget(ArchiveTreePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.entries != oldWidget.entries) {
      // If the new entry list is a superset of the old one (i.e. lazy
      // expansion just added children), keep the user's filter and expanded
      // state; otherwise treat it as a brand-new archive open and reset.
      final isExtension = widget.entries.length >= oldWidget.entries.length &&
          widget.entries.isNotEmpty &&
          oldWidget.entries.isNotEmpty &&
          widget.entries.first.expr == oldWidget.entries.first.expr;
      if (!isExtension) {
        _filterController.clear();
        _expanded.clear();
        _filterCollapsed.clear();
        _selectedExpr = null;
      }
      _flatCache = null;
      _expandedVersion++;
      _scheduleInitialBuild(widget.entries);
    } else if (widget.expandingArchives != oldWidget.expandingArchives) {
      // A node is loading/has loaded — just trigger a row repaint.
      _expandedVersion++;
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
        result.add(
          TreeNode(
            name: node.name,
            fullExpr: node.fullExpr,
            isArchive: node.isArchive,
            children: nameMatches ? node.children : filteredChildren,
            entry: node.entry,
          ),
        );
        if (filteredChildren.isNotEmpty) {
          autoExpand.add(node.fullExpr);
        }
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (_buildingTree) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('正在构建归档索引...', style: TextStyle(fontSize: 12)),
          ],
        ),
      );
    }

    List<TreeNode> displayTree;
    Set<String> effectiveExpanded;

    if (_filterText.isEmpty) {
      displayTree = _tree;
      effectiveExpanded = _expanded;
    } else {
      final autoExpand = <String>{};
      displayTree = _filterNodes(_tree, _filterText, autoExpand);
      effectiveExpanded = {..._expanded, ...autoExpand}
        ..removeAll(_filterCollapsed);
    }

    _effectiveExpanded = effectiveExpanded;

    // Memoize the flatten output across parent rebuilds.
    final cacheValid = _flatCache != null &&
        identical(_flatCacheTreeRef, displayTree) &&
        _flatCacheFilter == _filterText &&
        _flatCacheExpandedVersion == _expandedVersion;
    final List<_FlatNode> flatNodes;
    if (cacheValid) {
      flatNodes = _flatCache!;
    } else {
      flatNodes = <_FlatNode>[];
      _flattenWith(displayTree, 0, flatNodes, effectiveExpanded);
      _flatCache = flatNodes;
      _flatCacheTreeRef = displayTree;
      _flatCacheFilter = _filterText;
      _flatCacheExpandedVersion = _expandedVersion;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: FilterHistoryTextField(
            controller: _filterController,
            filterText: _filterText,
            hintText: '搜索文件...',
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
    // A node is expandable if it has children OR it's a lazy nested archive
    // whose children have not been loaded yet (entry.isArchive && empty).
    final isLazyArchive = node.entry?.isArchive == true && node.children.isEmpty;
    final hasChildren = node.children.isNotEmpty || isLazyArchive;
    final isExpanded = _effectiveExpanded.contains(node.fullExpr);
    final isSelected = _selectedExpr == node.fullExpr;
    final isLoading =
        node.entry != null && widget.expandingArchives.contains(node.entry!.expr);

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
                // Lazy: ask the host to load the children if needed.
                if (isLazyArchive && !isLoading) {
                  widget.onExpandArchive?.call(node.entry!.expr);
                }
              }
              _expandedVersion++;
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
              if (isLoading)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
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

  void _showContextMenu(BuildContext context, Offset position, TreeNode node) {
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
