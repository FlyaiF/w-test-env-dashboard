import '../../src/rust/api/zipr_api.dart';

/// A node in the diff tree.
class DiffTreeNode {
  final String name;
  final String fullExpr;
  final bool isArchive;
  final List<DiffTreeNode> children;

  /// Only set for leaf nodes (actual diff entries).
  final DiffEntry? diffEntry;

  /// Aggregate counts from this node and all descendants.
  int addedCount = 0;
  int removedCount = 0;
  int modifiedCount = 0;

  DiffTreeNode({
    required this.name,
    required this.fullExpr,
    this.isArchive = false,
    List<DiffTreeNode>? children,
    this.diffEntry,
  }) : children = children ?? [];

  bool get isLeaf => children.isEmpty && diffEntry != null;

  int get totalCount => addedCount + removedCount + modifiedCount;
}

/// Archive file extensions that represent nested archives.
const _archiveExtensions = {'.jar', '.war', '.zip', '.ear'};

bool _isArchiveFile(String name) {
  final lower = name.toLowerCase();
  return _archiveExtensions.any((ext) => lower.endsWith(ext));
}

/// Builds a hierarchical tree from a flat list of [DiffEntry].
///
/// Uses the same `!/` archive boundary and `/` directory separator
/// conventions as [buildTree] in archive_tree_builder.dart.
List<DiffTreeNode> buildDiffTree(List<DiffEntry> entries) {
  final root = <String, DiffTreeNode>{};

  for (final entry in entries) {
    final archiveSegments = entry.path.split('!/');

    // Strip filesystem prefix from first segment (show filename only)
    if (archiveSegments.isNotEmpty && archiveSegments[0].contains('/')) {
      archiveSegments[0] = archiveSegments[0].split('/').last;
    }

    _insertPath(root, archiveSegments, 0, [], entry);
  }

  final result = root.values.toList();
  _sortTree(result);
  computeAggregateCounts(result);
  return result;
}

void _insertPath(
  Map<String, DiffTreeNode> siblings,
  List<String> archiveSegments,
  int segIdx,
  List<String> exprParts,
  DiffEntry entry,
) {
  if (segIdx >= archiveSegments.length) return;

  final segment = archiveSegments[segIdx];
  final isLastArchiveSegment = segIdx == archiveSegments.length - 1;
  final pathParts = segment.split('/');

  _insertDirectory(
    siblings,
    pathParts,
    0,
    archiveSegments,
    segIdx,
    exprParts,
    entry,
    isLastArchiveSegment,
  );
}

void _insertDirectory(
  Map<String, DiffTreeNode> siblings,
  List<String> pathParts,
  int pathIdx,
  List<String> archiveSegments,
  int segIdx,
  List<String> exprParts,
  DiffEntry entry,
  bool isLastArchiveSegment,
) {
  if (pathIdx >= pathParts.length) return;

  final name = pathParts[pathIdx];
  if (name.isEmpty) return;

  final isLastPathPart = pathIdx == pathParts.length - 1;
  final currentExprParts = [...exprParts];
  if (segIdx > 0 && pathIdx == 0) {
    currentExprParts.add('!/');
  }
  if (pathIdx > 0) {
    currentExprParts.add('/');
  }
  currentExprParts.add(name);

  final fullExpr = currentExprParts.join('').replaceAll('/!/', '!/');

  if (!siblings.containsKey(name)) {
    final isArchive = _isArchiveFile(name);
    siblings[name] = DiffTreeNode(
      name: name,
      fullExpr: fullExpr,
      isArchive: isArchive,
      diffEntry: (isLastPathPart && isLastArchiveSegment) ? entry : null,
    );
  }

  final node = siblings[name]!;
  final childMap = <String, DiffTreeNode>{};
  for (final child in node.children) {
    childMap[child.name] = child;
  }

  if (isLastPathPart && !isLastArchiveSegment) {
    _insertPath(childMap, archiveSegments, segIdx + 1, currentExprParts, entry);
  } else if (!isLastPathPart) {
    _insertDirectory(
      childMap,
      pathParts,
      pathIdx + 1,
      archiveSegments,
      segIdx,
      currentExprParts,
      entry,
      isLastArchiveSegment,
    );
  }

  node.children
    ..clear()
    ..addAll(childMap.values);
}

/// Computes aggregate added/removed/modified counts via post-order traversal.
void computeAggregateCounts(List<DiffTreeNode> nodes) {
  for (final node in nodes) {
    if (node.children.isNotEmpty) {
      computeAggregateCounts(node.children);
      node.addedCount = 0;
      node.removedCount = 0;
      node.modifiedCount = 0;
      for (final child in node.children) {
        node.addedCount += child.addedCount;
        node.removedCount += child.removedCount;
        node.modifiedCount += child.modifiedCount;
      }
    } else if (node.diffEntry != null) {
      switch (node.diffEntry!.kind) {
        case 'added':
          node.addedCount = 1;
        case 'removed':
          node.removedCount = 1;
        case 'modified':
          node.modifiedCount = 1;
      }
    }
  }
}

/// Sorts tree: archives and directories first, then files, alphabetically.
void _sortTree(List<DiffTreeNode> nodes) {
  nodes.sort((a, b) {
    final aDir = a.children.isNotEmpty || a.isArchive;
    final bDir = b.children.isNotEmpty || b.isArchive;
    if (aDir && !bDir) return -1;
    if (!aDir && bDir) return 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  for (final node in nodes) {
    if (node.children.isNotEmpty) {
      _sortTree(node.children);
    }
  }
}
