import 'dart:convert';

import 'package:env_viewer/api/backend_client.dart';
import 'package:env_viewer/catalog/environment_store.dart';
import 'package:env_viewer/pages/catalog/catalog_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

Widget _wrap(EnvironmentStore store) {
  return ChangeNotifierProvider<EnvironmentStore>.value(
    value: store,
    child: const MaterialApp(home: Scaffold(body: CatalogPage())),
  );
}

void main() {
  testWidgets('creating an environment posts to the backend and confirms', (
    tester,
  ) async {
    http.Request? posted;
    final store = EnvironmentStore(
      BackendClient(
        baseUrl: 'http://test',
        httpClient: MockClient((req) async {
          if (req.method == 'POST') {
            posted = req;
            return http.Response(
              jsonEncode({'id': 1, 'name': 'ENV-NEW', 'components': []}),
              201,
            );
          }
          // GET: initial load (empty) and post-create reload (one env).
          final list = posted == null
              ? <Object>[]
              : [
                  {'id': 1, 'name': 'ENV-NEW', 'memo': null, 'components': []},
                ];
          return http.Response(jsonEncode(list), 200);
        }),
      ),
    );

    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();

    // Open the create dialog from the header button.
    await tester.tap(find.widgetWithText(FilledButton, '新建环境'));
    await tester.pumpAndSettle();
    expect(find.text('新建环境'), findsWidgets); // button + dialog title

    // Fill the name (first field inside the dialog) and save.
    final nameField = find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextFormField),
        )
        .first;
    await tester.enterText(nameField, 'ENV-NEW');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(posted, isNotNull);
    expect(posted!.url.path, '/api/environments');
    expect(jsonDecode(posted!.body)['name'], 'ENV-NEW');
    expect(find.text('环境已创建'), findsOneWidget); // success snackbar
  });

  testWidgets('deleting an environment asks for confirmation first', (
    tester,
  ) async {
    var deletes = 0;
    final store = EnvironmentStore(
      BackendClient(
        baseUrl: 'http://test',
        httpClient: MockClient((req) async {
          if (req.method == 'DELETE') {
            deletes++;
            return http.Response('', 204);
          }
          final list = deletes == 0
              ? [
                  {'id': 1, 'name': 'Alpha', 'memo': null, 'components': []},
                ]
              : <Object>[];
          return http.Response(jsonEncode(list), 200);
        }),
      ),
    );

    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();

    // Delete the selected environment; a confirmation dialog gates the call.
    await tester.tap(find.byTooltip('删除环境'));
    await tester.pumpAndSettle();
    expect(find.text('删除环境'), findsWidgets);
    expect(deletes, 0); // nothing deleted until confirmed

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(deletes, 1);
    expect(find.text('环境已删除'), findsOneWidget);
  });
}
