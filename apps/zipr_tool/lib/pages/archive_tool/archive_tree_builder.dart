import '../../src/rust/api/zipr_api.dart';

/// A node in the archive tree.
class TreeNode {
  final String name;
  final String fullExpr;
  final bool isArchive;
  final List<TreeNode> children;

  /// Only set for leaf nodes (actual entries).
  final ArchiveEntry? entry;

  TreeNode({
    required this.name,
    required this.fullExpr,
    this.isArchive = false,
    List<TreeNode>? children,
    this.entry,
  }) : children = children ?? [];

  bool get isLeaf => children.isEmpty && entry != null;
}

/// Archive file extensions that represent nested archives.
const _archiveExtensions = {'.jar', '.war', '.zip', '.ear'};

bool _isArchiveFile(String name) {
  final lower = name.toLowerCase();
  return _archiveExtensions.any((ext) => lower.endsWith(ext));
}

/// Builds a hierarchical tree from a flat list of [ArchiveEntry].
///
/// Entries use `!/` to separate nested archive boundaries and `/` for
/// directory separators within each archive level.
///
/// Example entry expr: `app.jar!/BOOT-INF/lib/module.jar!/com/Foo.class`
/// produces a tree:
///   app.jar (archive)
///     BOOT-INF/
///       lib/
///         module.jar (archive)
///           com/
///             Foo.class (leaf)
List<TreeNode> buildTree(List<ArchiveEntry> entries) {
  final root = <String, TreeNode>{};

  for (final entry in entries) {
    // Split on archive boundaries first
    final archiveSegments = entry.expr.split('!/');

    // First segment may be a full filesystem path — use only the filename
    // so the tree root shows "zipr.zip" instead of "/Users/.../zipr.zip"
    if (archiveSegments.isNotEmpty && archiveSegments[0].contains('/')) {
      archiveSegments[0] = archiveSegments[0].split('/').last;
    }

    _insertPath(root, archiveSegments, 0, [], entry);
  }

  final result = root.values.toList();
  _sortTree(result);
  return result;
}

void _insertPath(
  Map<String, TreeNode> siblings,
  List<String> archiveSegments,
  int segIdx,
  List<String> exprParts,
  ArchiveEntry entry,
) {
  if (segIdx >= archiveSegments.length) return;

  final segment = archiveSegments[segIdx];
  final isLastArchiveSegment = segIdx == archiveSegments.length - 1;

  // Split directory path within this archive level
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
  Map<String, TreeNode> siblings,
  List<String> pathParts,
  int pathIdx,
  List<String> archiveSegments,
  int segIdx,
  List<String> exprParts,
  ArchiveEntry entry,
  bool isLastArchiveSegment,
) {
  if (pathIdx >= pathParts.length) return;

  final name = pathParts[pathIdx];
  if (name.isEmpty) return;

  final isLastPathPart = pathIdx == pathParts.length - 1;
  final currentExprParts = [...exprParts];
  if (segIdx > 0 && pathIdx == 0) {
    // Add archive boundary
    currentExprParts.add('!/');
  }
  if (pathIdx > 0) {
    currentExprParts.add('/');
  }
  currentExprParts.add(name);

  final fullExpr = currentExprParts.join('').replaceAll('/!/', '!/');

  if (!siblings.containsKey(name)) {
    final isArchive = _isArchiveFile(name);
    siblings[name] = TreeNode(
      name: name,
      fullExpr: fullExpr,
      isArchive: isArchive,
      entry: (isLastPathPart && isLastArchiveSegment) ? entry : null,
    );
  }

  final node = siblings[name]!;
  final childMap = <String, TreeNode>{};
  for (final child in node.children) {
    childMap[child.name] = child;
  }

  if (isLastPathPart && !isLastArchiveSegment) {
    // Descend into nested archive
    _insertPath(childMap, archiveSegments, segIdx + 1, currentExprParts, entry);
  } else if (!isLastPathPart) {
    // Descend into directory
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

  // Sync children back
  node.children
    ..clear()
    ..addAll(childMap.values);
}

/// Sorts tree: archives and directories first, then files, alphabetically.
void _sortTree(List<TreeNode> nodes) {
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
