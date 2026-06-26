import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart'
    show AppThemeController, buildAppTheme;
import 'package:window_manager/window_manager.dart';

import 'api/backend_client.dart';
import 'catalog/environment_store.dart';
import 'pages/about/about_page.dart';
import 'pages/catalog/catalog_page.dart';
import 'widgets/app_scaffold.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(900, 600),
    center: true,
    title: '测试环境速查工具',
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(MyApp(backendClient: BackendClient()));
}

class MyApp extends StatelessWidget {
  final BackendClient backendClient;

  const MyApp({super.key, required this.backendClient});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppThemeController()..load()),
        Provider<BackendClient>.value(value: backendClient),
        ChangeNotifierProvider(create: (_) => EnvironmentStore(backendClient)),
      ],
      child: Consumer<AppThemeController>(
        builder: (context, themeController, _) {
          return MaterialApp(
            title: '测试环境速查工具',
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            darkTheme: buildAppTheme(brightness: Brightness.dark),
            themeMode: themeController.themeMode,
            home: const HomePage(),
          );
        },
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (i) => setState(() => _selectedIndex = i),
      child: IndexedStack(
        index: _selectedIndex,
        children: const [
          CatalogPage(),
          AboutPage(),
        ],
      ),
    );
  }
}
