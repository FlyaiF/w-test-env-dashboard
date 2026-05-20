import 'package:flutter/foundation.dart';

import '../src/rust/api/zipr_api.dart';
import 'zipr_bridge_interface.dart';

class ZiprService extends ChangeNotifier {
  final ZiprBridgeInterface _bridge;

  ZiprService({ZiprBridgeInterface? bridge})
    : _bridge = bridge ?? RealZiprBridge();

  String? _currentArchivePath;
  List<ArchiveEntry> _entries = [];
  List<DiffEntry> _diffEntries = [];
  List<UnresolvedEntry> _unresolvedEntries = [];
  String? _diffLeftPath;
  String? _diffRightPath;
  bool _loading = false;
  String? _error;
  String? _operationMessage;
  String? _lastBackupPath;
  Duration? _lastPatchApplyDuration;
  // Zip expressions of nested archives whose children have already been
  // merged into `_entries` (used by the tree to know which nodes are loaded).
  final Set<String> _expandedArchives = {};
  // In-flight expansion requests so concurrent expand taps don't dupe work.
  final Set<String> _expandingArchives = {};
  // Full list of every leaf path in the archive (across all nested levels),
  // populated lazily for Dart-side draft matching. Null until requested.
  List<String>? _allArchivePaths;

  String? get currentArchivePath => _currentArchivePath;
  List<ArchiveEntry> get entries => _entries;
  List<DiffEntry> get diffEntries => _diffEntries;
  List<UnresolvedEntry> get unresolvedEntries => _unresolvedEntries;
  String? get diffLeftPath => _diffLeftPath;
  String? get diffRightPath => _diffRightPath;
  bool get loading => _loading;
  String? get error => _error;
  String? get operationMessage => _operationMessage;
  String? get lastBackupPath => _lastBackupPath;
  Duration? get lastPatchApplyDuration => _lastPatchApplyDuration;
  Set<String> get expandedArchives => _expandedArchives;
  // Live view of in-flight expansions for the tree panel; not a snapshot.
  Set<String> get expandingArchivesView => _expandingArchives;
  bool isExpanding(String zipExpr) => _expandingArchives.contains(zipExpr);
  List<String>? get allArchivePaths => _allArchivePaths;

  void _beginOperation(String message, {bool loading = true}) {
    _loading = loading;
    _error = null;
    _operationMessage = message;
    notifyListeners();
  }

  void _updateOperation(String message) {
    _operationMessage = message;
    notifyListeners();
  }

  void _finishOperation() {
    _loading = false;
    _operationMessage = null;
    notifyListeners();
  }

  Future<void> listArchive(String path) async {
    _beginOperation('正在读取归档: $path');

    try {
      _entries = await _bridge.listArchive(path: path);
      if (_currentArchivePath != path) {
        _lastBackupPath = null;
        _expandedArchives.clear();
        _expandingArchives.clear();
        _allArchivePaths = null;
      }
      _currentArchivePath = path;
    } catch (e) {
      _error = e.toString();
      _entries = [];
    } finally {
      _finishOperation();
    }
  }

  void _clearArchiveDerivedCaches() {
    _expandedArchives.clear();
    _expandingArchives.clear();
    _allArchivePaths = null;
  }

  /// Lazily load the top-level entries of a nested archive identified by
  /// `zipExpr` and merge them into [entries]. Safe to call multiple times;
  /// repeated calls for an already-expanded archive are a no-op.
  Future<void> expandArchive(String zipExpr) async {
    if (_expandedArchives.contains(zipExpr)) return;
    if (_expandingArchives.contains(zipExpr)) return;
    _expandingArchives.add(zipExpr);
    _operationMessage = '正在展开: $zipExpr';
    notifyListeners();
    try {
      final children = await _bridge.listArchiveSegment(zipExpr: zipExpr);
      _entries = [..._entries, ...children];
      _expandedArchives.add(zipExpr);
    } catch (e) {
      _error = e.toString();
    } finally {
      _expandingArchives.remove(zipExpr);
      _operationMessage = null;
      notifyListeners();
    }
  }

  /// Populate [allArchivePaths] for Dart-side draft matching. No-op if
  /// already loaded for the current archive.
  Future<void> loadAllArchivePaths({bool silent = false}) async {
    if (_allArchivePaths != null) return;
    final archive = _currentArchivePath;
    if (archive == null) return;
    if (!silent) {
      _operationMessage = '正在扫描归档路径: $archive';
      notifyListeners();
    }
    try {
      _allArchivePaths = await _bridge.enumerateArchivePaths(path: archive);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    } finally {
      if (!silent) {
        _operationMessage = null;
        notifyListeners();
      }
    }
  }

  Future<void> extractEntry(String zipExpr, String outputPath) async {
    _beginOperation('正在提取: $zipExpr -> $outputPath');
    try {
      await _bridge.extractEntry(zipExpr: zipExpr, outputPath: outputPath);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    } finally {
      _finishOperation();
    }
  }

  Future<void> deleteEntry(String zipExpr) async {
    _beginOperation('正在删除: $zipExpr');

    try {
      await _bridge.deleteEntry(zipExpr: zipExpr);
      // Refresh list after delete
      if (_currentArchivePath != null) {
        _clearArchiveDerivedCaches();
        _updateOperation('正在刷新归档: $_currentArchivePath');
        _entries = await _bridge.listArchive(path: _currentArchivePath!);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _finishOperation();
    }
  }

  Future<void> replaceEntry(String zipExpr, String sourcePath) async {
    _beginOperation('正在替换: $zipExpr <- $sourcePath');

    try {
      await _bridge.replaceEntry(zipExpr: zipExpr, sourcePath: sourcePath);
      // Refresh list after replace
      if (_currentArchivePath != null) {
        _clearArchiveDerivedCaches();
        _updateOperation('正在刷新归档: $_currentArchivePath');
        _entries = await _bridge.listArchive(path: _currentArchivePath!);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _finishOperation();
    }
  }

  Future<void> diffArchives(String left, String right) async {
    _beginOperation('正在对比归档: $left <-> $right');

    try {
      _diffEntries = await _bridge.diffArchives(left: left, right: right);
      _diffLeftPath = left;
      _diffRightPath = right;
    } catch (e) {
      _error = e.toString();
      _diffEntries = [];
    } finally {
      _finishOperation();
    }
  }

  Future<DraftSummary> patchDraft(
    String archive,
    String fromDir,
    String output,
  ) async {
    _beginOperation('正在生成替换清单: $fromDir -> $output');

    try {
      final summary = await _bridge.patchDraft(
        archive: archive,
        fromDir: fromDir,
        output: output,
      );
      _unresolvedEntries = summary.unresolvedEntries;
      // Pre-warm the matching cache; subsequent extends are pure Dart.
      // Fire-and-forget so the draft itself returns promptly.
      // ignore: unawaited_futures
      loadAllArchivePaths(silent: true);
      return summary;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    } finally {
      _finishOperation();
    }
  }

  Future<ApplySummary?> patchApply(
    String archive,
    String spec, {
    bool dryRun = false,
  }) async {
    _beginOperation(dryRun ? '正在 dry-run: $spec' : '正在替换归档: $spec -> $archive');

    try {
      final stopwatch = Stopwatch()..start();
      final summary = await _bridge.patchApply(
        archive: archive,
        spec: spec,
        dryRun: dryRun,
      );
      stopwatch.stop();
      _lastPatchApplyDuration = stopwatch.elapsed;
      // Refresh list after apply (unless dry-run)
      if (!dryRun && _currentArchivePath != null) {
        _clearArchiveDerivedCaches();
        _updateOperation('正在刷新归档: $_currentArchivePath');
        _entries = await _bridge.listArchive(path: _currentArchivePath!);
        _lastBackupPath = summary.backupPath;
      }
      return summary;
    } catch (e) {
      _error = e.toString();
      _lastPatchApplyDuration = null;
      return null;
    } finally {
      _finishOperation();
    }
  }

  Future<DraftSummary?> patchDraftExtend(
    String archive,
    String specPath,
    List<String> additionalSources,
  ) async {
    _beginOperation('正在追加替换文件: ${additionalSources.join(", ")}');

    try {
      final summary = await _bridge.patchDraftExtend(
        archive: archive,
        specPath: specPath,
        additionalSources: additionalSources,
      );
      _unresolvedEntries = summary.unresolvedEntries;
      return summary;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _finishOperation();
    }
  }

  Future<bool> restoreArchiveBackup(String archive, String backup) async {
    _beginOperation('正在回滚归档: $backup -> $archive');

    try {
      await _bridge.restoreArchiveBackup(archive: archive, backup: backup);
      _clearArchiveDerivedCaches();
      _updateOperation('正在刷新归档: $archive');
      _entries = await _bridge.listArchive(path: archive);
      _lastBackupPath = null;
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _finishOperation();
    }
  }

  Future<DraftSummary?> patchResolve(
    String specPath,
    List<Resolution> resolutions,
  ) async {
    _beginOperation('正在应用解析: $specPath');

    try {
      final summary = await _bridge.patchResolve(
        specPath: specPath,
        resolutions: resolutions,
      );
      _unresolvedEntries = summary.unresolvedEntries;
      return summary;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _finishOperation();
    }
  }

  Future<DraftSummary?> readPatchSpec(String specPath) async {
    _error = null;
    try {
      final summary = await _bridge.readPatchSpec(specPath: specPath);
      _unresolvedEntries = summary.unresolvedEntries;
      return summary;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearDiff() {
    _diffEntries = [];
    _diffLeftPath = null;
    _diffRightPath = null;
    notifyListeners();
  }
}
