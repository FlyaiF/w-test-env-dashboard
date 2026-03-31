import 'dart:typed_data';

import '../src/rust/api/zipr_api.dart' as zipr_api;
import '../src/rust/api/zipr_api.dart';

/// Abstract interface for zipr bridge operations.
/// The real implementation delegates to FRB-generated functions; tests use a mock.
abstract class ZiprBridgeInterface {
  Future<List<ArchiveEntry>> listArchive({required String path});

  Future<Uint8List> extractEntry({
    required String zipExpr,
    required String outputPath,
  });

  Future<void> deleteEntry({required String zipExpr});

  Future<void> replaceEntry({
    required String zipExpr,
    required String sourcePath,
  });

  Future<List<DiffEntry>> diffArchives({
    required String left,
    required String right,
  });

  Future<DraftSummary> patchDraft({
    required String archive,
    required String fromDir,
    required String output,
  });

  Future<ApplySummary> patchApply({
    required String archive,
    required String spec,
    required bool dryRun,
  });
}

/// Production implementation backed by flutter_rust_bridge.
class RealZiprBridge implements ZiprBridgeInterface {
  @override
  Future<List<ArchiveEntry>> listArchive({required String path}) =>
      zipr_api.listArchive(path: path);

  @override
  Future<Uint8List> extractEntry({
    required String zipExpr,
    required String outputPath,
  }) =>
      zipr_api.extractEntry(zipExpr: zipExpr, outputPath: outputPath);

  @override
  Future<void> deleteEntry({required String zipExpr}) =>
      zipr_api.deleteEntry(zipExpr: zipExpr);

  @override
  Future<void> replaceEntry({
    required String zipExpr,
    required String sourcePath,
  }) =>
      zipr_api.replaceEntry(zipExpr: zipExpr, sourcePath: sourcePath);

  @override
  Future<List<DiffEntry>> diffArchives({
    required String left,
    required String right,
  }) =>
      zipr_api.diffArchives(left: left, right: right);

  @override
  Future<DraftSummary> patchDraft({
    required String archive,
    required String fromDir,
    required String output,
  }) =>
      zipr_api.patchDraft(archive: archive, fromDir: fromDir, output: output);

  @override
  Future<ApplySummary> patchApply({
    required String archive,
    required String spec,
    required bool dryRun,
  }) =>
      zipr_api.patchApply(archive: archive, spec: spec, dryRun: dryRun);
}
