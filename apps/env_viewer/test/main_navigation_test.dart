import 'package:env_viewer/api/backend_client.dart';
import 'package:env_viewer/catalog/environment_store.dart';
import 'package:env_viewer/config/config_service.dart';
import 'package:env_viewer/config/config_store.dart';
import 'package:env_viewer/inventory/inventory_store.dart';
import 'package:env_viewer/main.dart';
import 'package:env_viewer/services/access/access_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('opens Resource Inventory from the application navigation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final client = BackendClient(
      baseUrl: 'http://test',
      httpClient: MockClient((_) async => http.Response('[]', 200)),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<BackendClient>.value(value: client),
          Provider<AccessLauncher>.value(value: AccessLauncher(client)),
          ChangeNotifierProvider<EnvironmentStore>(
            create: (_) => EnvironmentStore(client),
          ),
          ChangeNotifierProvider<InventoryStore>(
            create: (_) => InventoryStore(client),
          ),
          ChangeNotifierProvider<ConfigStore>.value(
            value: ConfigStore(AppConfig.empty()),
          ),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('资源库存'), findsOneWidget);
    await tester.tap(find.text('资源库存'));
    await tester.pumpAndSettle();

    expect(find.text('资源清单'), findsOneWidget);
  });
}
