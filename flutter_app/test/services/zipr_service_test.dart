import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:test_env_dashboard/services/zipr_bridge_interface.dart';
import 'package:test_env_dashboard/services/zipr_service.dart';
import 'package:test_env_dashboard/src/rust/api/zipr_api.dart';

/// Simple mock bridge for testing — no code generation needed.
class MockZiprBridge implements ZiprBridgeInterface {
  List<ArchiveEntry> listResult = [];
  List<DiffEntry> diffResult = [];
  DraftSummary? draftResult;
  ApplySummary? applyResult;
  Object? errorToThrow;

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
    return listResult;
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
      ),
      ArchiveEntry(
        expr: 'app.jar!/lib.jar!/Util.class',
        size: BigInt.from(2048),
        compressedSize: BigInt.from(1024),
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
    });

    test('listArchive sets loading=true during call', () async {
      mock.listResult = testEntries;
      final loadingStates = <bool>[];
      service.addListener(() => loadingStates.add(service.loading));

      await service.listArchive('/path/to/app.jar');

      // First notification: loading=true, second: loading=false
      expect(loadingStates, [true, false]);
    });

    test('listArchive sets error on bridge failure', () async {
      mock.errorToThrow = Exception('file not found');

      await service.listArchive('/bad/path');

      expect(service.error, contains('file not found'));
      expect(service.entries, isEmpty);
      expect(service.loading, false);
    });

    test('extractEntry calls bridge with correct arguments', () async {
      await service.extractEntry(
        'app.jar!/Main.class',
        '/tmp/Main.class',
      );

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
      );

      final summary =
          await service.patchDraft('/app.jar', '/patches', '/out.toml');

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

      expect(summary.replaced, BigInt.from(5));
      expect(summary.deleted, BigInt.from(2));
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
