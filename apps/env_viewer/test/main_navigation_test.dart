import 'package:env_viewer/api/backend_client.dart';
import 'package:env_viewer/catalog/environment_store.dart';
import 'package:env_viewer/config/config_service.dart';
import 'package:env_viewer/config/config_store.dart';
import 'package:env_viewer/inventory/inventory_store.dart';
import 'package:env_viewer/main.dart';
import 'package:env_viewer/remote_files/remote_file_store.dart';
import 'package:env_viewer/services/access/access_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart' show AppThemeController;

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
          ChangeNotifierProvider<AppThemeController>(
            create: (_) => AppThemeController(),
          ),
          ChangeNotifierProvider<RemoteFileStore>(
            create: (_) => RemoteFileStore(client),
          ),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();

    // The sidebar nav item (the page itself is offstage until selected).
    expect(find.text('资源清单'), findsOneWidget);
    await tester.tap(find.text('资源清单'));
    await tester.pumpAndSettle();

    // Nav item + page header, and the inventory tabs are now on stage.
    expect(find.text('资源清单'), findsNWidgets(2));
    expect(find.text('服务器'), findsOneWidget);

    // The 日志文件 page is reachable from the same nav group.
    await tester.tap(find.text('日志文件'));
    await tester.pumpAndSettle();
    expect(find.textContaining('从左侧选择组件'), findsOneWidget);
  });
}
