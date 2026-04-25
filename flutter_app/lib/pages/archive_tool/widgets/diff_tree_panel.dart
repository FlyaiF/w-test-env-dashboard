import 'package:flutter/material.dart';

import '../../../src/rust/api/zipr_api.dart';
import '../../../widgets/filter_history_text_field.dart';
import '../diff_tree_builder.dart';

class DiffTreePanel extends StatefulWidget {
  final List<DiffEntry> diffEntries;
  final String leftPath;
  final String rightPath;
  final VoidCallback? onClose;

  const DiffTreePanel({
    super.key,
    required this.diffEntries,
    required this.leftPath,
    required this.rightPath,
    this.onClose,
  });

  @override
  State<DiffTreePanel> createState() => _DiffTreePanelState();
}

class _DiffTreePanelState extends State<DiffTreePanel> {
  late List<DiffTreeNode> _leftTree;
  late List<DiffTreeNode> _rightTree;
  late int _addedCount;
  late int _removedCount;
  late int _modifiedCount;

  final Set<String> _expanded = {};
  final TextEditingController _filterController = TextEditingController();
  String _filterText = '';
  final Set<String> _filterCollapsed = {};

  @override
  void initState() {
    super.initState();
    _buildTrees();
    _filterController.addListener(_onFilterChanged);
  }

  @override
  void didUpdateWidget(DiffTreePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.diffEntries != oldWidget.diffEntries) {
      _buildTrees();
      _filterController.clear();
    }
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  void _onFilterChanged() {
    final newFilter = _filterController.text.toLowerCase();
    if (newFilter != _filterText) {
      setState(() {
        _filterText = newFilter;
        _filterCollapsed.clear();
      });
    }
  }

  void _buildTrees() {
    final leftEntries = widget.diffEntries
        .where((e) => e.kind == 'removed' || e.kind == 'modified')
        .toList();
    final rightEntries = widget.diffEntries
        .where((e) => e.kind == 'added' || e.kind == 'modified')
        .toList();

    _leftTree = buildDiffTree(leftEntries);
    _rightTree = buildDiffTree(rightEntries);

    _addedCount = widget.diffEntries.where((e) => e.kind == 'added').length;
    _removedCount = widget.diffEntries.where((e) => e.kind == 'removed').length;
    _modifiedCount = widget.diffEntries
        .where((e) => e.kind == 'modified')
        .length;
  }

  Set<String> _effectiveExpanded() {
    if (_filterText.isEmpty) return _expanded;
    final autoExpand = <String>{};
    _filterNodes(_leftTree, _filterText, autoExpand);
    _filterNodes(_rightTree, _filterText, autoExpand);
    return {..._expanded, ...autoExpand}..removeAll(_filterCollapsed);
  }

  List<DiffTreeNode> _filterNodes(
    List<DiffTreeNode> nodes,
    String filter,
    Set<String> autoExpand,
  ) {
    final result = <DiffTreeNode>[];
    for (final node in nodes) {
      final nameMatches = node.name.toLowerCase().contains(filter);
      final filteredChildren = _filterNodes(node.children, filter, autoExpand);
      if (nameMatches || filteredChildren.isNotEmpty) {
        result.add(
          DiffTreeNode(
              name: node.name,
              fullExpr: node.fullExpr,
              isArchive: node.isArchive,
              children: nameMatches ? node.children : filteredChildren,
              diffEntry: node.diffEntry,
            )
            ..addedCount = node.addedCount
            ..removedCount = node.removedCount
            ..modifiedCount = node.modifiedCount,
        );
        if (filteredChildren.isNotEmpty) {
          autoExpand.add(node.fullExpr);
        }
      }
    }
    return result;
  }

  void _toggleExpand(String fullExpr) {
    setState(() {
      if (_expanded.contains(fullExpr)) {
        _expanded.remove(fullExpr);
        if (_filterText.isNotEmpty) _filterCollapsed.add(fullExpr);
      } else {
        _expanded.add(fullExpr);
        _filterCollapsed.remove(fullExpr);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final expanded = _effectiveExpanded();

    List<DiffTreeNode> leftDisplay;
    List<DiffTreeNode> rightDisplay;
    if (_filterText.isEmpty) {
      leftDisplay = _leftTree;
      rightDisplay = _rightTree;
    } else {
      final autoExpand = <String>{};
      leftDisplay = _filterNodes(_leftTree, _filterText, autoExpand);
      rightDisplay = _filterNodes(_rightTree, _filterText, autoExpand);
    }

    final leftFlat = <_FlatDiffNode>[];
    _flattenWith(leftDisplay, 0, leftFlat, expanded);
    final rightFlat = <_FlatDiffNode>[];
    _flattenWith(rightDisplay, 0, rightFlat, expanded);

    return Column(
      children: [
        _buildSummaryBar(context),
        _buildFilterBar(),
        const Divider(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildTreeSide(
                  context,
                  leftFlat,
                  _leftFileName(),
                  expanded,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _buildTreeSide(
                  context,
                  rightFlat,
                  _rightFileName(),
                  expanded,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryBar(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: theme.colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          Icon(
            Icons.compare_arrows,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text('差异对比', style: theme.textTheme.titleSmall),
          const SizedBox(width: 16),
          _countBadge('+$_addedCount', Colors.green.shade600),
          const SizedBox(width: 8),
          _countBadge('-$_removedCount', Colors.red.shade600),
          const SizedBox(width: 8),
          _countBadge('~$_modifiedCount', Colors.blue.shade600),
          const SizedBox(width: 16),
          Text(
            '共 ${widget.diffEntries.length} 项差异',
            style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
          ),
          const Spacer(),
          if (widget.onClose != null)
            IconButton(
              onPressed: widget.onClose,
              icon: const Icon(Icons.close, size: 18),
              tooltip: '关闭对比',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }

  Widget _countBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
          fontFamily: 'Sarasa Mono SC',
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: FilterHistoryTextField(
        controller: _filterController,
        filterText: _filterText,
        hintText: '搜索差异文件...',
      ),
    );
  }

  Widget _buildTreeSide(
    BuildContext context,
    List<_FlatDiffNode> flatNodes,
    String archiveName,
    Set<String> expanded,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Text(
            archiveName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurfaceVariant,
              fontFamily: 'Sarasa Mono SC',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: flatNodes.isEmpty
              ? Center(
                  child: Text(
                    '无变更',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: flatNodes.length,
                  itemBuilder: (context, index) =>
                      _buildRow(context, flatNodes[index], expanded),
                ),
        ),
      ],
    );
  }

  Widget _buildRow(
    BuildContext context,
    _FlatDiffNode flat,
    Set<String> expanded,
  ) {
    final node = flat.node;
    final hasChildren = node.children.isNotEmpty;
    final isExpanded = expanded.contains(node.fullExpr);

    final color = _nodeColor(node);

    return InkWell(
      onTap: hasChildren ? () => _toggleExpand(node.fullExpr) : null,
      child: Padding(
        padding: EdgeInsets.only(
          left: 12.0 + flat.depth * 20.0,
          top: 3,
          bottom: 3,
          right: 8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (hasChildren)
                  Icon(
                    isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                  )
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 4),
                Icon(_iconForNode(node), size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    node.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: color,
                      fontFamily: 'Sarasa Mono SC',
                    ),
                  ),
                ),
                if (hasChildren) _buildAggregBadges(node),
                if (node.diffEntry != null) _buildKindTag(node.diffEntry!.kind),
              ],
            ),
            if (node.diffEntry != null && node.diffEntry!.contentChanged)
              Padding(
                padding: const EdgeInsets.only(left: 46),
                child: Text(
                  'content changed',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ),
            if (node.diffEntry != null)
              for (final meta in node.diffEntry!.metadataChanges)
                Padding(
                  padding: const EdgeInsets.only(left: 46),
                  child: Text(
                    meta,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildKindTag(String kind) {
    final (tag, color) = switch (kind) {
      'added' => ('A', Colors.green.shade600),
      'removed' => ('D', Colors.red.shade600),
      'modified' => ('M', Colors.blue.shade600),
      _ => ('?', Colors.grey),
    };
    return Container(
      width: 20,
      alignment: Alignment.center,
      child: Text(
        tag,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontFamily: 'Sarasa Mono SC',
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildAggregBadges(DiffTreeNode node) {
    final parts = <Widget>[];
    if (node.addedCount > 0) {
      parts.add(
        Text(
          '+${node.addedCount}',
          style: TextStyle(
            fontSize: 11,
            color: Colors.green.shade600,
            fontFamily: 'Sarasa Mono SC',
          ),
        ),
      );
    }
    if (node.modifiedCount > 0) {
      if (parts.isNotEmpty) parts.add(const SizedBox(width: 4));
      parts.add(
        Text(
          '~${node.modifiedCount}',
          style: TextStyle(
            fontSize: 11,
            color: Colors.blue.shade600,
            fontFamily: 'Sarasa Mono SC',
          ),
        ),
      );
    }
    if (node.removedCount > 0) {
      if (parts.isNotEmpty) parts.add(const SizedBox(width: 4));
      parts.add(
        Text(
          '-${node.removedCount}',
          style: TextStyle(
            fontSize: 11,
            color: Colors.red.shade600,
            fontFamily: 'Sarasa Mono SC',
          ),
        ),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: parts);
  }

  Color? _nodeColor(DiffTreeNode node) {
    if (node.diffEntry != null) {
      return switch (node.diffEntry!.kind) {
        'added' => Colors.green.shade700,
        'removed' => Colors.red.shade700,
        'modified' => Colors.blue.shade700,
        _ => null,
      };
    }
    // Directory: use dominant child color
    if (node.removedCount > 0 &&
        node.addedCount == 0 &&
        node.modifiedCount == 0) {
      return Colors.red.shade700;
    }
    if (node.addedCount > 0 &&
        node.removedCount == 0 &&
        node.modifiedCount == 0) {
      return Colors.green.shade700;
    }
    if (node.modifiedCount > 0 &&
        node.removedCount == 0 &&
        node.addedCount == 0) {
      return Colors.blue.shade700;
    }
    return null; // mixed changes, use default color
  }

  IconData _iconForNode(DiffTreeNode node) {
    if (node.isArchive) return Icons.inventory_2;
    if (node.children.isNotEmpty) return Icons.folder_outlined;
    final lower = node.name.toLowerCase();
    if (lower.endsWith('.class')) return Icons.code;
    if (lower.endsWith('.xml') || lower.endsWith('.properties')) {
      return Icons.settings;
    }
    return Icons.insert_drive_file_outlined;
  }

  String _leftFileName() => widget.leftPath.split('/').last;
  String _rightFileName() => widget.rightPath.split('/').last;

  void _flattenWith(
    List<DiffTreeNode> nodes,
    int depth,
    List<_FlatDiffNode> out,
    Set<String> expanded,
  ) {
    for (final node in nodes) {
      out.add(_FlatDiffNode(node: node, depth: depth));
      if (expanded.contains(node.fullExpr) && node.children.isNotEmpty) {
        _flattenWith(node.children, depth + 1, out, expanded);
      }
    }
  }
}

class _FlatDiffNode {
  final DiffTreeNode node;
  final int depth;
  _FlatDiffNode({required this.node, required this.depth});
}
