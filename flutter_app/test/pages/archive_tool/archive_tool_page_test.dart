import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:test_env_dashboard/pages/archive_tool/archive_tool_page.dart';
import 'package:test_env_dashboard/services/zipr_service.dart';
import 'package:test_env_dashboard/src/rust/api/zipr_api.dart';

import '../../services/zipr_service_test.dart';

Widget _wrapWithProviders(ZiprService service) {
  return MaterialApp(
    home: Scaffold(
      body: ChangeNotifierProvider.value(
        value: service,
        child: const ArchiveToolPage(),
      ),
    ),
  );
}

void main() {
  group('ArchiveToolPage', () {
    late MockZiprBridge mock;
    late ZiprService service;

    setUp(() {
      mock = MockZiprBridge();
      service = ZiprService(bridge: mock);
    });

    testWidgets('shows empty state when no archive loaded', (tester) async {
      await tester.pumpWidget(_wrapWithProviders(service));

      expect(find.text('选择或拖入归档文件开始操作'), findsOneWidget);
      expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
    });

    testWidgets('shows toolbar buttons', (tester) async {
      await tester.pumpWidget(_wrapWithProviders(service));

      expect(find.text('打开归档文件'), findsOneWidget);
      expect(find.text('对比归档'), findsOneWidget);
      expect(find.text('归档工具'), findsOneWidget);
    });

    testWidgets('shows tree and detail panel after archive loaded',
        (tester) async {
      mock.listResult = [
        ArchiveEntry(
          expr: 'Main.class',
          size: BigInt.from(1024),
          compressedSize: BigInt.from(512),
        ),
      ];
      await service.listArchive('/test.jar');

      await tester.pumpWidget(_wrapWithProviders(service));
      await tester.pump();

      // Tree panel shows the entry
      expect(find.text('Main.class'), findsOneWidget);
      // Detail panel shows placeholder
      expect(find.text('选择文件查看详情'), findsOneWidget);
    });

    testWidgets('shows loading indicator', (tester) async {
      await tester.pumpWidget(_wrapWithProviders(service));

      // Track loading states via listener
      mock.listResult = [];
      final loadingStates = <bool>[];
      service.addListener(() => loadingStates.add(service.loading));

      await service.listArchive('/slow.jar');

      // Verify loading was set to true during the call
      expect(loadingStates, contains(true));
    });

    testWidgets('shows error bar on failure', (tester) async {
      mock.errorToThrow = Exception('test error');
      await service.listArchive('/bad.jar');

      await tester.pumpWidget(_wrapWithProviders(service));
      await tester.pump();

      expect(find.textContaining('test error'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows batch replace button after archive loaded',
        (tester) async {
      mock.listResult = [
        ArchiveEntry(
          expr: 'file.txt',
          size: BigInt.from(10),
          compressedSize: BigInt.from(5),
        ),
      ];
      await service.listArchive('/test.jar');

      await tester.pumpWidget(_wrapWithProviders(service));
      await tester.pump();

      expect(find.text('批量替换'), findsOneWidget);
    });

    testWidgets('shows archive path in toolbar after loading', (tester) async {
      mock.listResult = [];
      await service.listArchive('/path/to/my-archive.jar');

      await tester.pumpWidget(_wrapWithProviders(service));
      await tester.pump();

      expect(find.text('/path/to/my-archive.jar'), findsOneWidget);
    });
  });
}
