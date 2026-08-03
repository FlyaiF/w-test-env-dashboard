/// Suggestion logic for the 日志文件 free-path bar, kept pure for testing.
///
/// Two sources merge:
///  * **Known paths** (component 日志位置 presets, open-tab paths) matched by
///    *keywords* — every whitespace-separated token of the input must appear
///    somewhere in the path (case-insensitive), so typing `gw` or `trust log`
///    finds `/home/ta66/trust-ops/logs/gw.log` without any prefix discipline.
///  * **Remote directory entries** (when a live session can list them): the
///    input is split at its last `/`; entries of that directory whose name
///    contains the trailing fragment complete in place, directories suffixed
///    `/` so a pick keeps the completion flowing.
library;

/// Lists entry names of a remote directory (directories suffixed `/`), or
/// empty when listing is unavailable. Implementations must not throw.
typedef DirectoryLister = Future<List<String>> Function(String dirPath);

Future<List<String>> buildPathSuggestions({
  required String input,
  required List<String> knownPaths,
  DirectoryLister? listDirectory,
  int limit = 12,
}) async {
  final trimmed = input.trim();
  final suggestions = <String>[];

  // Remote completions first: when the user is walking a directory they are
  // navigating, siblings beat historical shortcuts.
  final slash = trimmed.lastIndexOf('/');
  if (listDirectory != null && slash >= 0) {
    final dir = trimmed.substring(0, slash + 1);
    final fragment = trimmed.substring(slash + 1).toLowerCase();
    final entries = await listDirectory(dir == '/' ? '/' : dir);
    for (final entry in entries) {
      if (fragment.isEmpty || entry.toLowerCase().contains(fragment)) {
        suggestions.add('$dir$entry');
      }
    }
    suggestions.sort();
  }

  // Keyword matches over known paths: every token must occur somewhere.
  final tokens = trimmed.toLowerCase()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();
  for (final path in knownPaths) {
    final lower = path.toLowerCase();
    if (tokens.every(lower.contains) && !suggestions.contains(path)) {
      suggestions.add(path);
    }
  }

  return suggestions.length <= limit
      ? suggestions
      : suggestions.sublist(0, limit);
}
