import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zipr_tool/pages/archive_tool/local_draft_extender.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'local_draft_extender_test_',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'matches files by relative path and basename, then appends TOML',
    () async {
      final sourceDir = Directory('${tempDir.path}/sources');
      await Directory('${sourceDir.path}/com').create(recursive: true);
      await File('${sourceDir.path}/com/Foo.class').writeAsString('foo');
      await File('${sourceDir.path}/bar.txt').writeAsString('bar');
      await File(
        '${sourceDir.path}/patch.draft.orig.toml',
      ).writeAsString('skip');
      final spec = File('${sourceDir.path}/patch.draft.toml');
      await spec.writeAsString('version = 1\n');

      final result = await LocalDraftExtender.extend(
        specPath: spec.path,
        sourceRoots: [sourceDir.path],
        allArchivePaths: [
          '/tmp/app.zip!/com/Foo.class',
          '/tmp/app.zip!/nested/bar.txt',
        ],
        existingSources: const {},
      );

      expect(result.newEntries, hasLength(2));
      expect(result.newUnresolved, isEmpty);
      expect(result.skippedDuplicates, 0);
      final toml = await spec.readAsString();
      expect(toml, contains('target = "/tmp/app.zip!/com/Foo.class"'));
      expect(toml, contains('target = "/tmp/app.zip!/nested/bar.txt"'));
      expect(toml, isNot(contains('patch.draft.orig.toml')));
    },
  );

  test('skips sources already present in the spec', () async {
    final source = File('${tempDir.path}/Foo.class');
    await source.writeAsString('foo');
    final spec = File('${tempDir.path}/patch.draft.toml');
    await spec.writeAsString('version = 1\n');
    final normalized = source.path.replaceAll('\\', '/');

    final result = await LocalDraftExtender.extend(
      specPath: spec.path,
      sourceRoots: [source.path],
      allArchivePaths: ['/tmp/app.zip!/Foo.class'],
      existingSources: {normalized},
    );

    expect(result.newEntries, isEmpty);
    expect(result.newUnresolved, isEmpty);
    expect(result.skippedDuplicates, 1);
    expect(await spec.readAsString(), 'version = 1\n');
  });

  test('records ambiguous and unmatched sources as unresolved', () async {
    final dup = File('${tempDir.path}/dup.txt');
    final missing = File('${tempDir.path}/missing.txt');
    await dup.writeAsString('dup');
    await missing.writeAsString('missing');
    final spec = File('${tempDir.path}/patch.draft.toml');
    await spec.writeAsString('version = 1\n');

    final result = await LocalDraftExtender.extend(
      specPath: spec.path,
      sourceRoots: [dup.path, missing.path],
      allArchivePaths: ['/tmp/app.zip!/a/dup.txt', '/tmp/app.zip!/b/dup.txt'],
      existingSources: const {},
    );

    expect(result.newEntries, isEmpty);
    expect(result.newUnresolved, hasLength(2));
    final byReason = {for (final u in result.newUnresolved) u.reason: u};
    expect(byReason['multiple targets']!.candidates, hasLength(2));
    expect(byReason['no target matched']!.candidates, isEmpty);
    final toml = await spec.readAsString();
    expect(toml, contains('reason = "multiple targets"'));
    expect(toml, contains('reason = "no target matched"'));
  });

  test(
    'removes empty unresolved array before appending unresolved tables',
    () async {
      final missing = File('${tempDir.path}/missing.txt');
      await missing.writeAsString('missing');
      final spec = File('${tempDir.path}/patch.draft.toml');
      await spec.writeAsString('version = 1\nunresolved = []\n');

      final result = await LocalDraftExtender.extend(
        specPath: spec.path,
        sourceRoots: [missing.path],
        allArchivePaths: const [],
        existingSources: const {},
      );

      expect(result.newUnresolved, hasLength(1));
      final toml = await spec.readAsString();
      expect(toml, isNot(contains('unresolved = []')));
      expect(toml, contains('[[unresolved]]'));
    },
  );

  test('sanitizes existing broken unresolved table shape', () {
    final toml = LocalDraftExtender.sanitizeUnresolvedTables('''
version = 1
unresolved = []

[[unresolved]]
source = "missing.txt"
reason = "no target matched"
candidates = []
''');

    expect(toml, isNot(contains('unresolved = []')));
    expect(toml, contains('[[unresolved]]'));
  });

  test('escapes quotes in TOML strings', () async {
    final source = File('${tempDir.path}/quote"file.txt');
    await source.writeAsString('quoted');
    final spec = File('${tempDir.path}/patch.draft.toml');
    await spec.writeAsString('version = 1\n');

    final result = await LocalDraftExtender.extend(
      specPath: spec.path,
      sourceRoots: [source.path],
      allArchivePaths: ['/tmp/app.zip!/quote"file.txt'],
      existingSources: const {},
    );

    expect(result.newEntries, hasLength(1));
    final toml = await spec.readAsString();
    final escapedSource = source.path
        .replaceAll('\\', '/')
        .replaceAll('"', r'\"');
    expect(toml, contains('target = "/tmp/app.zip!/quote\\"file.txt"'));
    expect(toml, contains('source = "$escapedSource"'));
  });
}
