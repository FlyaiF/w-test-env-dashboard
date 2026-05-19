import 'dart:io';

import '../../src/rust/api/zipr_api.dart';

/// Result of a local (Dart-side) draft extend operation.
class LocalExtendResult {
  /// Patch entries newly added in this extend (target -> source pairs).
  final List<({String target, String source})> newEntries;

  /// Unresolved sources newly added (no match or multiple matches).
  final List<UnresolvedEntry> newUnresolved;

  /// Source paths that were skipped because they already appear in the spec.
  final int skippedDuplicates;

  LocalExtendResult({
    required this.newEntries,
    required this.newUnresolved,
    required this.skippedDuplicates,
  });

  int get added => newEntries.length + newUnresolved.length;
}

/// Match new source paths against an archive's full path list and append the
/// resulting entries to an on-disk patch spec TOML file. All work happens in
/// Dart — no FFI round-trip to Rust.
class LocalDraftExtender {
  static final _emptyUnresolvedArrayLine = RegExp(
    r'^\s*unresolved\s*=\s*\[\s*\]\s*(?:\r?\n)?',
    multiLine: true,
  );

  /// Rust serializes an empty unresolved list as `unresolved = []`. When the
  /// Dart extender later appends `[[unresolved]]` tables, TOML sees that as a
  /// duplicate root key. Drop the empty array form before table entries exist.
  static String sanitizeUnresolvedTables(String toml) {
    if (!toml.contains('[[unresolved]]')) return toml;
    return toml.replaceAll(_emptyUnresolvedArrayLine, '');
  }

  /// Walks [sourceRoots] (each may be a file or directory), matches files
  /// against [allArchivePaths], appends new entries to [specPath], and
  /// returns the structured result.
  ///
  /// [existingSources] is the set of `source` strings already present in the
  /// spec; duplicates are skipped.
  static Future<LocalExtendResult> extend({
    required String specPath,
    required List<String> sourceRoots,
    required List<String> allArchivePaths,
    required Set<String> existingSources,
  }) async {
    final inputs = await _collectInputs(sourceRoots);
    final (byFull, byName) = _buildLookups(allArchivePaths);

    final newEntries = <({String target, String source})>[];
    final newUnresolved = <UnresolvedEntry>[];
    var skipped = 0;

    // Track sources seen in this extend so a single call with duplicate inputs
    // doesn't double-add either.
    final seen = <String>{...existingSources};

    for (final input in inputs) {
      if (!seen.add(input.sourceNorm)) {
        skipped++;
        continue;
      }

      final fullMatch = byFull[input.relNorm];
      if (fullMatch != null) {
        newEntries.add((target: fullMatch, source: input.sourceNorm));
        continue;
      }
      final nameMatches = byName[input.base];
      if (nameMatches != null && nameMatches.length == 1) {
        newEntries.add((target: nameMatches.first, source: input.sourceNorm));
        continue;
      }
      if (nameMatches != null && nameMatches.length > 1) {
        newUnresolved.add(
          UnresolvedEntry(
            source: input.sourceNorm,
            reason: 'multiple targets',
            candidates: List.of(nameMatches),
          ),
        );
        continue;
      }
      newUnresolved.add(
        UnresolvedEntry(
          source: input.sourceNorm,
          reason: 'no target matched',
          candidates: const [],
        ),
      );
    }

    if (newEntries.isNotEmpty || newUnresolved.isNotEmpty) {
      await _appendToSpec(specPath, newEntries, newUnresolved);
    }

    return LocalExtendResult(
      newEntries: newEntries,
      newUnresolved: newUnresolved,
      skippedDuplicates: skipped,
    );
  }

  static Future<List<_Input>> _collectInputs(List<String> roots) async {
    final out = <_Input>[];
    for (final root in roots) {
      final type = await FileSystemEntity.type(root);
      if (type == FileSystemEntityType.file) {
        final base = root.split(RegExp(r'[/\\]')).last;
        out.add(
          _Input(
            sourceNorm: _normalize(root),
            relNorm: _normalize(base),
            base: base,
          ),
        );
      } else if (type == FileSystemEntityType.directory) {
        final dir = Directory(root);
        await for (final entity in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is! File) continue;
          final src = entity.path;
          final basename = src.split(RegExp(r'[/\\]')).last;
          if (basename == 'patch.draft.toml' ||
              basename == 'patch.draft.orig.toml') {
            continue;
          }
          final rel = src.startsWith(root) && src.length > root.length
              ? src.substring(root.length).replaceFirst(RegExp(r'^[/\\]'), '')
              : basename;
          out.add(
            _Input(
              sourceNorm: _normalize(src),
              relNorm: _normalize(rel),
              base: basename,
            ),
          );
        }
      }
    }
    return out;
  }

  static (Map<String, String>, Map<String, List<String>>) _buildLookups(
    List<String> allArchivePaths,
  ) {
    final byFull = <String, String>{};
    final byName = <String, List<String>>{};
    for (final expr in allArchivePaths) {
      final idx = expr.indexOf('!/');
      if (idx < 0) continue;
      final rel = expr.substring(idx + 2);
      if (rel.isEmpty) continue;
      // Match the Rust matcher: the full key may have nested `!/` separators;
      // the basename matcher only uses the trailing path segment.
      byFull[rel] = expr;
      final base = rel.split(RegExp(r'[/!]')).last;
      byName.putIfAbsent(base, () => <String>[]).add(expr);
    }
    return (byFull, byName);
  }

  static String _normalize(String path) => path.replaceAll('\\', '/');

  static Future<void> _appendToSpec(
    String specPath,
    List<({String target, String source})> entries,
    List<UnresolvedEntry> unresolved,
  ) async {
    final buf = StringBuffer();
    for (final e in entries) {
      buf
        ..writeln()
        ..writeln('[[entry]]')
        ..writeln('target = ${_tomlString(e.target)}')
        ..writeln('source = ${_tomlString(e.source)}')
        ..writeln('action = "replace"')
        ..writeln('method = "inherit"')
        ..writeln('level = "inherit"')
        ..writeln('mtime = "source"')
        ..writeln('comment = "inherit"');
    }
    for (final u in unresolved) {
      buf
        ..writeln()
        ..writeln('[[unresolved]]')
        ..writeln('source = ${_tomlString(u.source)}')
        ..writeln('reason = ${_tomlString(u.reason)}')
        ..writeln('candidates = [${u.candidates.map(_tomlString).join(', ')}]');
    }
    final f = File(specPath);
    final appended = buf.toString();
    if (appended.contains('[[unresolved]]')) {
      final existing = await f.exists() ? await f.readAsString() : '';
      final sanitized = sanitizeUnresolvedTables(existing + appended);
      await f.writeAsString(sanitized, flush: true);
      return;
    }
    await f.writeAsString(appended, mode: FileMode.append, flush: true);
  }

  /// TOML basic-string serialization for paths and reasons (handles `\` and `"`).
  static String _tomlString(String s) {
    final escaped = s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }
}

class _Input {
  final String sourceNorm;
  final String relNorm;
  final String base;
  _Input({required this.sourceNorm, required this.relNorm, required this.base});
}
