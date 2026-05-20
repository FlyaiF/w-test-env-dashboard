import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zipr_tool/services/zipr_bridge_interface.dart';
import 'package:zipr_tool/services/zipr_service.dart';
import 'package:zipr_tool/src/rust/api/zipr_api.dart';

/// Simple mock bridge for testing — no code generation needed.
class MockZiprBridge implements ZiprBridgeInterface {
  List<ArchiveEntry> listResult = [];
  List<DiffEntry> diffResult = [];
  DraftSummary? draftResult;
  ApplySummary? applyResult;
  Object? errorToThrow;
  Completer<List<ArchiveEntry>>? listArchiveCompleter;

  // Call tracking
  final calls = <String>[];

  void reset() {
    calls.clear();
    errorToThrow = null;
  }

  @override
  Future<List<ArchiveEntry>> listArchive({required String path}) async {
    calls.add('listArchive:$path');
    if (errorToThrow != null) throw errorToThrow!;
    if (listArchiveCompleter != null) return listArchiveCompleter!.future;
    return listResult;
  }

  List<ArchiveEntry> segmentResult = [];
  List<String> enumerateResult = [];

  @override
  Future<List<ArchiveEntry>> listArchiveSegment({
    required String zipExpr,
  }) async {
    calls.add('listArchiveSegment:$zipExpr');
    if (errorToThrow != null) throw errorToThrow!;
    return segmentResult;
  }

  @override
  Future<List<String>> enumerateArchivePaths({required String path}) async {
    calls.add('enumerateArchivePaths:$path');
    if (errorToThrow != null) throw errorToThrow!;
    return enumerateResult;
  }

  @override
  Future<Uint8List> extractEntry({
    required String zipExpr,
    required String outputPath,
  }) async {
    calls.add('extractEntry:$zipExpr:$outputPath');
    if (errorToThrow != null) throw errorToThrow!;
    return Uint8List(0);
  }

  @override
  Future<void> deleteEntry({required String zipExpr}) async {
    calls.add('deleteEntry:$zipExpr');
    if (errorToThrow != null) throw errorToThrow!;
  }

  @override
  Future<void> replaceEntry({
    required String zipExpr,
    required String sourcePath,
  }) async {
    calls.add('replaceEntry:$zipExpr:$sourcePath');
    if (errorToThrow != null) throw errorToThrow!;
  }

  @override
  Future<List<DiffEntry>> diffArchives({
    required String left,
    required String right,
  }) async {
    calls.add('diffArchives:$left:$right');
    if (errorToThrow != null) throw errorToThrow!;
    return diffResult;
  }

  @override
  Future<DraftSummary> patchDraft({
    required String archive,
    required String fromDir,
    required String output,
  }) async {
    calls.add('patchDraft:$archive:$fromDir:$output');
    if (errorToThrow != null) throw errorToThrow!;
    return draftResult!;
  }

  @override
  Future<ApplySummary> patchApply({
    required String archive,
    required String spec,
    required bool dryRun,
  }) async {
    calls.add('patchApply:$archive:$spec:$dryRun');
    if (errorToThrow != null) throw errorToThrow!;
    return applyResult!;
  }

  @override
  Future<DraftSummary> readPatchSpec({required String specPath}) async {
    calls.add('readPatchSpec:$specPath');
    if (errorToThrow != null) throw errorToThrow!;
    return draftResult!;
  }

  @override
  Future<DraftSummary> patchResolve({
    required String specPath,
    required List<Resolution> resolutions,
  }) async {
    calls.add('patchResolve:$specPath');
    if (errorToThrow != null) throw errorToThrow!;
    return draftResult!;
  }

  @override
  Future<DraftSummary> patchDraftExtend({
    required String archive,
    required String specPath,
    required List<String> additionalSources,
  }) async {
    calls.add(
      'patchDraftExtend:$archive:$specPath:${additionalSources.join(",")}',
    );
    if (errorToThrow != null) throw errorToThrow!;
    return draftResult!;
  }

  @override
  Future<void> restoreArchiveBackup({
    required String archive,
    required String backup,
  }) async {
    calls.add('restoreArchiveBackup:$archive:$backup');
    if (errorToThrow != null) throw errorToThrow!;
  }
}

void main() {
  group('ZiprService', () {
    late MockZiprBridge mock;
    late ZiprService service;

    final testEntries = [
      ArchiveEntry(
        expr: 'app.jar!/Main.class',
        size: BigInt.from(1024),
        compressedSize: BigInt.from(512),
        isArchive: false,
      ),
      ArchiveEntry(
        expr: 'app.jar!/lib.jar!/Util.class',
        size: BigInt.from(2048),
        compressedSize: BigInt.from(1024),
        isArchive: false,
      ),
    ];

    setUp(() {
      mock = MockZiprBridge();
      service = ZiprService(bridge: mock);
    });

    test('initial state', () {
      expect(service.currentArchivePath, isNull);
      expect(service.entries, isEmpty);
      expect(service.diffEntries, isEmpty);
      expect(service.loading, false);
      expect(service.error, isNull);
      expect(service.operationMessage, isNull);
      expect(service.lastPatchApplyDuration, isNull);
    });

    test('listArchive sets entries and notifies listeners', () async {
      mock.listResult = testEntries;
      var notified = false;
      service.addListener(() => notified = true);

      await service.listArchive('/path/to/app.jar');

      expect(service.entries.length, 2);
      expect(service.currentArchivePath, '/path/to/app.jar');
      expect(service.loading, false);
      expect(service.error, isNull);
      expect(notified, true);
      expect(service.operationMessage, isNull);
    });

    test('listArchive sets loading=true during call', () async {
      mock.listResult = testEntries;
      final loadingStates = <bool>[];
      service.addListener(() => loadingStates.add(service.loading));

      await service.listArchive('/path/to/app.jar');

      // First notification: loading=true, second: loading=false
      expect(loadingStates, [true, false]);
    });

    test('listArchive exposes operation message while running', () async {
      mock.listArchiveCompleter = Completer<List<ArchiveEntry>>();

      final future = service.listArchive('/slow.jar');

      expect(service.loading, true);
      expect(service.operationMessage, '正在读取归档: /slow.jar');

      mock.listArchiveCompleter!.complete(testEntries);
      await future;

      expect(service.loading, false);
      expect(service.operationMessage, isNull);
    });

    test('listArchive sets error on bridge failure', () async {
      mock.errorToThrow = Exception('file not found');

      await service.listArchive('/bad/path');

      expect(service.error, contains('file not found'));
      expect(service.entries, isEmpty);
      expect(service.loading, false);
      expect(service.operationMessage, isNull);
    });

    test('extractEntry calls bridge with correct arguments', () async {
      await service.extractEntry('app.jar!/Main.class', '/tmp/Main.class');

      expect(mock.calls, ['extractEntry:app.jar!/Main.class:/tmp/Main.class']);
    });

    test('extractEntry rethrows on failure', () async {
      mock.errorToThrow = Exception('extract failed');

      expect(
        () => service.extractEntry('expr', '/out'),
        throwsA(isA<Exception>()),
      );
    });

    test('deleteEntry refreshes list after success', () async {
      mock.listResult = testEntries;
      await service.listArchive('/path/to/app.jar');
      mock.reset();
      mock.listResult = [testEntries[1]]; // one fewer after delete

      await service.deleteEntry('app.jar!/Main.class');

      expect(mock.calls, [
        'deleteEntry:app.jar!/Main.class',
        'listArchive:/path/to/app.jar',
      ]);
      expect(service.entries.length, 1);
    });

    test('replaceEntry refreshes list after success', () async {
      mock.listResult = testEntries;
      await service.listArchive('/path/to/app.jar');
      mock.reset();
      mock.listResult = testEntries;

      await service.replaceEntry('app.jar!/Main.class', '/new/Main.class');

      expect(mock.calls, [
        'replaceEntry:app.jar!/Main.class:/new/Main.class',
        'listArchive:/path/to/app.jar',
      ]);
    });

    test('diffArchives sets diffEntries and notifies', () async {
      mock.diffResult = [
        DiffEntry(
          path: 'added.txt',
          kind: 'added',
          contentChanged: true,
          metadataChanges: [],
        ),
      ];

      await service.diffArchives('/left.jar', '/right.jar');

      expect(service.diffEntries.length, 1);
      expect(service.diffEntries[0].kind, 'added');
      expect(service.loading, false);
    });

    test('diffArchives sets error on failure', () async {
      mock.errorToThrow = Exception('diff failed');

      await service.diffArchives('/left.jar', '/right.jar');

      expect(service.error, contains('diff failed'));
      expect(service.diffEntries, isEmpty);
    });

    test('patchDraft returns summary with spec TOML', () async {
      mock.draftResult = DraftSummary(
        matched: BigInt.from(3),
        unresolved: BigInt.from(1),
        specToml: 'version = 1\n',
        unresolvedEntries: [],
      );

      final summary = await service.patchDraft(
        '/app.jar',
        '/patches',
        '/out.toml',
      );

      expect(summary.matched, BigInt.from(3));
      expect(summary.unresolved, BigInt.from(1));
      expect(summary.specToml, 'version = 1\n');
    });

    test('patchApply returns replaced/deleted counts', () async {
      mock.listResult = testEntries;
      await service.listArchive('/app.jar');
      mock.reset();
      mock.applyResult = ApplySummary(
        replaced: BigInt.from(5),
        deleted: BigInt.from(2),
      );
      mock.listResult = testEntries;

      final summary = await service.patchApply('/app.jar', '/spec.toml');

      expect(summary!.replaced, BigInt.from(5));
      expect(summary.deleted, BigInt.from(2));
      expect(service.lastPatchApplyDuration, isNotNull);
    });

    test('patchApply dry-run does not refresh list', () async {
      mock.listResult = testEntries;
      await service.listArchive('/app.jar');
      mock.reset();
      mock.applyResult = ApplySummary(
        replaced: BigInt.from(5),
        deleted: BigInt.from(0),
      );

      await service.patchApply('/app.jar', '/spec.toml', dryRun: true);

      // Only patchApply called, no listArchive refresh
      expect(mock.calls, ['patchApply:/app.jar:/spec.toml:true']);
    });

    test('patchApply clears archive-derived caches after mutation', () async {
      final archiveEntry = ArchiveEntry(
        expr: '/app.jar!/lib/inner.jar',
        size: BigInt.from(12),
        compressedSize: BigInt.from(8),
        isArchive: true,
      );
      final childEntry = ArchiveEntry(
        expr: '/app.jar!/lib/inner.jar!/Foo.class',
        size: BigInt.from(20),
        compressedSize: BigInt.from(10),
        isArchive: false,
      );
      mock.listResult = [archiveEntry];
      await service.listArchive('/app.jar');
      mock.segmentResult = [childEntry];
      await service.expandArchive(archiveEntry.expr);
      mock.enumerateResult = [childEntry.expr];
      await service.loadAllArchivePaths();
      expect(service.expandedArchives, contains(archiveEntry.expr));
      expect(service.allArchivePaths, isNotNull);

      mock.reset();
      mock.applyResult = ApplySummary(
        replaced: BigInt.one,
        deleted: BigInt.zero,
        backupPath: '/app.jar.bak-test',
      );
      mock.listResult = [archiveEntry];

      await service.patchApply('/app.jar', '/spec.toml');

      expect(service.expandedArchives, isEmpty);
      expect(service.expandingArchivesView, isEmpty);
      expect(service.allArchivePaths, isNull);
      expect(service.lastBackupPath, '/app.jar.bak-test');
    });

    test('restoreArchiveBackup clears archive-derived caches', () async {
      final archiveEntry = ArchiveEntry(
        expr: '/app.jar!/lib/inner.jar',
        size: BigInt.from(12),
        compressedSize: BigInt.from(8),
        isArchive: true,
      );
      final childEntry = ArchiveEntry(
        expr: '/app.jar!/lib/inner.jar!/Foo.class',
        size: BigInt.from(20),
        compressedSize: BigInt.from(10),
        isArchive: false,
      );
      mock.listResult = [archiveEntry];
      await service.listArchive('/app.jar');
      mock.segmentResult = [childEntry];
      await service.expandArchive(archiveEntry.expr);
      mock.enumerateResult = [childEntry.expr];
      await service.loadAllArchivePaths();

      mock.reset();
      mock.listResult = [archiveEntry];
      final ok = await service.restoreArchiveBackup('/app.jar', '/app.jar.bak');

      expect(ok, true);
      expect(service.expandedArchives, isEmpty);
      expect(service.expandingArchivesView, isEmpty);
      expect(service.allArchivePaths, isNull);
      expect(service.lastBackupPath, isNull);
    });

    test('clearError clears the error state', () async {
      mock.errorToThrow = Exception('some error');
      await service.listArchive('/bad');
      expect(service.error, isNotNull);

      service.clearError();
      expect(service.error, isNull);
    });

    test('clearDiff clears diff entries', () async {
      mock.diffResult = [
        DiffEntry(
          path: 'f.txt',
          kind: 'added',
          contentChanged: true,
          metadataChanges: [],
        ),
      ];
      await service.diffArchives('/a', '/b');
      expect(service.diffEntries, isNotEmpty);

      service.clearDiff();
      expect(service.diffEntries, isEmpty);
    });
  });
}
