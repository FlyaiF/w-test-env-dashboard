import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zipr_tool/pages/archive_tool/widgets/detail_panel.dart';
import 'package:zipr_tool/src/rust/api/zipr_api.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('DetailPanel', () {
    testWidgets('entry mode: shows placeholder when no entry selected',
        (tester) async {
      await tester.pumpWidget(_wrap(const DetailPanel(
        mode: DetailMode.entry,
        selectedEntry: null,
      )));

      expect(find.text('选择文件查看详情'), findsOneWidget);
    });

    testWidgets('entry mode: shows entry details', (tester) async {
      final entry = ArchiveEntry(
        expr: 'app.jar!/com/Example.class',
        size: BigInt.from(2048),
        compressedSize: BigInt.from(1024),
      );

      await tester.pumpWidget(_wrap(DetailPanel(
        mode: DetailMode.entry,
        selectedEntry: entry,
      )));

      expect(find.text('文件详情'), findsOneWidget);
      expect(find.text('app.jar!/com/Example.class'), findsOneWidget);
      expect(find.text('2.0 KB'), findsWidgets); // size
      expect(find.text('1.0 KB'), findsWidgets); // compressed
      expect(find.text('50.0%'), findsOneWidget); // ratio
    });

    testWidgets('diff mode: shows empty message when no diffs',
        (tester) async {
      await tester.pumpWidget(_wrap(const DetailPanel(
        mode: DetailMode.diff,
        diffEntries: [],
      )));

      expect(find.text('无差异'), findsOneWidget);
    });

    testWidgets('diff mode: shows color-coded A/D/M entries', (tester) async {
      final diffs = [
        DiffEntry(
          path: 'new-file.txt',
          kind: 'added',
          contentChanged: true,
          metadataChanges: [],
        ),
        DiffEntry(
          path: 'old-file.txt',
          kind: 'removed',
          contentChanged: false,
          metadataChanges: [],
        ),
        DiffEntry(
          path: 'changed.txt',
          kind: 'modified',
          contentChanged: true,
          metadataChanges: ['method: Deflated -> Stored'],
        ),
      ];

      await tester.pumpWidget(_wrap(DetailPanel(
        mode: DetailMode.diff,
        diffEntries: diffs,
      )));

      expect(find.text('差异对比'), findsOneWidget);
      expect(find.text('新增: 1  删除: 1  修改: 1'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('D'), findsOneWidget);
      expect(find.text('M'), findsOneWidget);
      expect(find.text('new-file.txt'), findsOneWidget);
      expect(find.text('old-file.txt'), findsOneWidget);
      expect(find.text('changed.txt'), findsOneWidget);
    });

    testWidgets('patch mode: shows buttons and draft area', (tester) async {
      var draftCalled = false;
      var dryRunCalled = false;
      var applyCalled = false;

      await tester.pumpWidget(_wrap(DetailPanel(
        mode: DetailMode.patch,
        patchSpecToml: 'version = 1\n[[entry]]\ntarget = "file.txt"\n',
        onPatchDraft: () => draftCalled = true,
        onPatchDryRun: () => dryRunCalled = true,
        onPatchApply: () => applyCalled = true,
      )));

      expect(find.text('批量替换'), findsOneWidget);
      expect(find.text('生成清单'), findsOneWidget);
      expect(find.text('预演'), findsOneWidget);
      expect(find.text('应用替换'), findsOneWidget);
      expect(find.textContaining('version = 1'), findsOneWidget);

      await tester.tap(find.text('生成清单'));
      expect(draftCalled, true);

      await tester.tap(find.text('预演'));
      expect(dryRunCalled, true);

      await tester.tap(find.text('应用替换'));
      expect(applyCalled, true);
    });

    testWidgets('patch mode: buttons disabled when no spec', (tester) async {
      await tester.pumpWidget(_wrap(const DetailPanel(
        mode: DetailMode.patch,
        patchSpecToml: null,
      )));

      // Dry-run and apply buttons should be disabled (no spec yet)
      final dryRunButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '预演'),
      );
      expect(dryRunButton.onPressed, isNull);
    });
  });
}
