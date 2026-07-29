import 'package:env_viewer/inventory/inventory_view.dart';
import 'package:env_viewer/pages/inventory/inventory_editors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'server editor keeps the password out of the metadata payload and '
    'returns it as the write-only secret',
    (tester) async {
      ServerEditorResult? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  submitted = await showServerEditor(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('新建服务器'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('server-host-field')),
        'app01.internal',
      );
      await tester.enterText(
        find.byKey(const ValueKey('server-ssh-host-field')),
        'gateway.internal',
      );
      await tester.enterText(
        find.byKey(const ValueKey('server-ssh-port-field')),
        '2222',
      );
      await tester.enterText(
        find.byKey(const ValueKey('server-ssh-username-field')),
        'deploy',
      );
      await tester.enterText(
        find.byKey(const ValueKey('server-password-field')),
        's3cret-pw',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      final input = submitted?.input;
      expect(input?.host, 'app01.internal');
      expect(input?.os, 'LINUX');
      expect(input?.ssh?.host, 'gateway.internal');
      expect(input?.ssh?.port, 2222);
      expect(input?.ssh?.username, 'deploy');
      expect(submitted?.secret, 's3cret-pw');
      expect(input?.toJson().toString(), isNot(contains('s3cret-pw')));
      expect(input?.toJson().toString(), isNot(contains('password')));
      expect(input?.toJson().toString(), isNot(contains('secret')));
    },
  );

  testWidgets('server editor returns a null secret when the field stays empty', (
    tester,
  ) async {
    ServerEditorResult? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                submitted = await showServerEditor(
                  context,
                  existing: const ServerView(
                    id: 3,
                    host: 'app01.internal',
                    os: 'LINUX',
                    hasSecret: true,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The write-only field is never pre-filled, and the edit form reports
    // secret presence without revealing anything.
    expect(find.text('当前已设置密码'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
    expect(submitted?.secret, isNull);
  });

  testWidgets(
    'database editor keeps the password out of the metadata payload and '
    'returns it as the write-only secret',
    (tester) async {
      DatabaseEditorResult? submitted;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  submitted = await showDatabaseEditor(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('新建数据库'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('database-role-field')),
        'business',
      );
      await tester.enterText(
        find.byKey(const ValueKey('database-host-field')),
        'db01.internal',
      );
      await tester.enterText(
        find.byKey(const ValueKey('database-port-field')),
        '1521',
      );
      await tester.enterText(
        find.byKey(const ValueKey('database-service-field')),
        'ORCL',
      );
      await tester.enterText(
        find.byKey(const ValueKey('database-username-field')),
        'app_user',
      );
      await tester.enterText(
        find.byKey(const ValueKey('database-password-field')),
        'db-s3cret',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      final input = submitted?.input;
      expect(input?.role, 'business');
      expect(input?.type, 'ORACLE');
      expect(input?.connection?.host, 'db01.internal');
      expect(input?.connection?.port, 1521);
      expect(input?.connection?.serviceName, 'ORCL');
      expect(input?.connection?.username, 'app_user');
      expect(submitted?.secret, 'db-s3cret');
      expect(input?.toJson().toString(), isNot(contains('db-s3cret')));
      expect(input?.toJson().toString(), isNot(contains('password')));
      expect(input?.toJson().toString(), isNot(contains('secret')));
    },
  );

  testWidgets('server editor rejects an SSH port outside the valid range', (
    tester,
  ) async {
    ServerEditorResult? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                submitted = await showServerEditor(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('server-host-field')),
      'app01.internal',
    );
    await tester.enterText(
      find.byKey(const ValueKey('server-ssh-port-field')),
      '70000',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('端口应为 1-65535'), findsOneWidget);
    expect(find.text('新建服务器'), findsOneWidget);
    expect(submitted, isNull);
  });

  testWidgets('database editor rejects a non-numeric port', (tester) async {
    DatabaseEditorResult? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                submitted = await showDatabaseEditor(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('database-port-field')),
      'not-a-port',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('端口应为 1-65535'), findsOneWidget);
    expect(find.text('新建数据库'), findsOneWidget);
    expect(submitted, isNull);
  });
}
