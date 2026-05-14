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

  String? get currentArchivePath => _currentArchivePath;
  List<ArchiveEntry> get entries => _entries;
  List<DiffEntry> get diffEntries => _diffEntries;
  List<UnresolvedEntry> get unresolvedEntries => _unresolvedEntries;
  String? get diffLeftPath => _diffLeftPath;
  String? get diffRightPath => _diffRightPath;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> listArchive(String path) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _entries = await _bridge.listArchive(path: path);
      _currentArchivePath = path;
    } catch (e) {
      _error = e.toString();
      _entries = [];
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> extractEntry(String zipExpr, String outputPath) async {
    try {
      await _bridge.extractEntry(zipExpr: zipExpr, outputPath: outputPath);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> deleteEntry(String zipExpr) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      await _bridge.deleteEntry(zipExpr: zipExpr);
      // Refresh list after delete
      if (_currentArchivePath != null) {
        _entries = await _bridge.listArchive(path: _currentArchivePath!);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> replaceEntry(String zipExpr, String sourcePath) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      await _bridge.replaceEntry(zipExpr: zipExpr, sourcePath: sourcePath);
      // Refresh list after replace
      if (_currentArchivePath != null) {
        _entries = await _bridge.listArchive(path: _currentArchivePath!);
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> diffArchives(String left, String right) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _diffEntries = await _bridge.diffArchives(left: left, right: right);
      _diffLeftPath = left;
      _diffRightPath = right;
    } catch (e) {
      _error = e.toString();
      _diffEntries = [];
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<DraftSummary> patchDraft(
    String archive,
    String fromDir,
    String output,
  ) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final summary = await _bridge.patchDraft(
        archive: archive,
        fromDir: fromDir,
        output: output,
      );
      _unresolvedEntries = summary.unresolvedEntries;
      return summary;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<ApplySummary?> patchApply(
    String archive,
    String spec, {
    bool dryRun = false,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final summary = await _bridge.patchApply(
        archive: archive,
        spec: spec,
        dryRun: dryRun,
      );
      // Refresh list after apply (unless dry-run)
      if (!dryRun && _currentArchivePath != null) {
        _entries = await _bridge.listArchive(path: _currentArchivePath!);
      }
      return summary;
    } catch (e) {
      _error = e.toString();
      return null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<DraftSummary?> patchResolve(
    String specPath,
    List<Resolution> resolutions,
  ) async {
    _loading = true;
    _error = null;
    notifyListeners();

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
      _loading = false;
      notifyListeners();
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
