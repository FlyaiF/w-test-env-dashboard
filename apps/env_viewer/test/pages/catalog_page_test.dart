import 'dart:convert';

import 'package:env_viewer/api/backend_client.dart';
import 'package:env_viewer/catalog/environment_store.dart';
import 'package:env_viewer/pages/catalog/catalog_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

EnvironmentStore _storeReturning(Object json) {
  return EnvironmentStore(
    BackendClient(
      baseUrl: 'http://test',
      httpClient: MockClient((_) async => http.Response(jsonEncode(json), 200)),
    ),
  );
}

Widget _wrap(EnvironmentStore store) {
  return ChangeNotifierProvider<EnvironmentStore>.value(
    value: store,
    child: const MaterialApp(home: Scaffold(body: CatalogPage())),
  );
}

void main() {
  testWidgets('renders the environment list and selected detail read-only', (
    tester,
  ) async {
    final store = _storeReturning([
      {
        'id': 1,
        'name': 'Alpha',
        'memo': '主集成环境',
        'components': [
          {
            'id': 10,
            'role': 'GATEWAY',
            'version': '1.2.3',
            'versionProbe': 'HTTP',
            'collectionStatus': 'OK',
            'url': 'https://alpha.test/gw',
          },
        ],
      },
      {'id': 2, 'name': 'Beta', 'memo': null, 'components': []},
    ]);

    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();

    // List shows both environments.
    expect(find.text('Alpha'), findsWidgets);
    expect(find.text('Beta'), findsOneWidget);

    // First environment is auto-selected; its component renders with the
    // localized role label and version — read-only (no edit/save controls).
    expect(find.text('网关'), findsOneWidget);
    expect(find.text('1.2.3'), findsOneWidget);
    expect(find.text('正常'), findsOneWidget); // collection status chip
    expect(find.text('HTTP 接口'), findsOneWidget); // version probe label
    expect(find.byIcon(Icons.save), findsNothing);
  });

  testWidgets('shows an empty state when the backend returns nothing', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(_storeReturning([])));
    await tester.pumpAndSettle();

    expect(find.text('暂无环境'), findsOneWidget);
  });

  testWidgets('shows a localized error banner when the backend fails', (
    tester,
  ) async {
    final store = EnvironmentStore(
      BackendClient(
        baseUrl: 'http://test',
        httpClient: MockClient((_) async => http.Response('boom', 500)),
      ),
    );

    await tester.pumpWidget(_wrap(store));
    await tester.pumpAndSettle();

    expect(find.textContaining('500'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });
}
