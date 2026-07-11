import 'package:env_viewer/api/dto/database_input.dart';
import 'package:env_viewer/api/dto/server_input.dart';
import 'package:env_viewer/pages/inventory/inventory_editors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('server editor returns only non-secret connection metadata', (
    tester,
  ) async {
    ServerInput? submitted;
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
    expect(find.textContaining('密码'), findsNothing);
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
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(submitted?.host, 'app01.internal');
    expect(submitted?.os, 'LINUX');
    expect(submitted?.ssh?.host, 'gateway.internal');
    expect(submitted?.ssh?.port, 2222);
    expect(submitted?.ssh?.username, 'deploy');
    expect(submitted?.toJson().toString(), isNot(contains('密码')));
    expect(submitted?.toJson().toString(), isNot(contains('password')));
  });

  testWidgets('database editor returns only non-secret connection metadata', (
    tester,
  ) async {
    DatabaseInput? submitted;
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
    expect(find.textContaining('密码'), findsNothing);
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
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(submitted?.role, 'business');
    expect(submitted?.type, 'ORACLE');
    expect(submitted?.connection?.host, 'db01.internal');
    expect(submitted?.connection?.port, 1521);
    expect(submitted?.connection?.serviceName, 'ORCL');
    expect(submitted?.connection?.username, 'app_user');
    expect(submitted?.toJson().toString(), isNot(contains('密码')));
    expect(submitted?.toJson().toString(), isNot(contains('password')));
  });

  testWidgets('server editor rejects an SSH port outside the valid range', (
    tester,
  ) async {
    ServerInput? submitted;
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
    DatabaseInput? submitted;
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
