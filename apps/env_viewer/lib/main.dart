import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart'
    show AppThemeController, buildAppTheme;
import 'package:window_manager/window_manager.dart';

import 'api/backend_client.dart';
import 'catalog/environment_store.dart';
import 'config/config_store.dart';
import 'inventory/inventory_store.dart';
import 'pages/about/about_page.dart';
import 'services/access/access_launcher.dart';
import 'pages/catalog/catalog_page.dart';
import 'pages/inventory/inventory_page.dart';
import 'pages/remote_files/remote_files_page.dart';
import 'pages/settings/settings_page.dart';
import 'remote_files/remote_file_store.dart';
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

  // Backend URL precedence: the ENV_DASHBOARD_BACKEND_URL env var wins (and is
  // shown locked in Settings); otherwise the saved in-app value; otherwise the
  // BackendClient's localhost default (null → default).
  final envUrl = Platform.environment['ENV_DASHBOARD_BACKEND_URL'];
  final configStore = await ConfigStore.load(backendUrlEnvOverride: envUrl);
  final effectiveUrl = (envUrl != null && envUrl.isNotEmpty)
      ? envUrl
      : configStore.config.backendBaseUrl;

  runApp(
    MyApp(
      backendClient: BackendClient(baseUrl: effectiveUrl),
      configStore: configStore,
    ),
  );
}

class MyApp extends StatelessWidget {
  final BackendClient backendClient;
  final ConfigStore configStore;

  const MyApp({
    super.key,
    required this.backendClient,
    required this.configStore,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppThemeController()..load()),
        Provider<BackendClient>.value(value: backendClient),
        ChangeNotifierProvider<ConfigStore>.value(value: configStore),
        // Brokers Server/Database credentials on demand and launches the user's
        // own SSH/DB tools with them (ADR-0005); persists no secrets.
        Provider<AccessLauncher>(create: (_) => AccessLauncher(backendClient)),
        ChangeNotifierProvider(create: (_) => InventoryStore(backendClient)),
        ChangeNotifierProvider(create: (_) => EnvironmentStore(backendClient)),
        // Open remote-log/file tabs; brokers SSH credentials per open and
        // keeps sessions alive while the user navigates elsewhere.
        ChangeNotifierProvider(create: (_) => RemoteFileStore(backendClient)),
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

  /// Last jump signal handled: a catalog 查看日志 action bumps the store's
  /// signal, and this shell answers by switching to the 日志文件 page.
  int _handledJumpSignal = 0;
  RemoteFileStore? _remoteFiles;

  @override
  void initState() {
    super.initState();
    _remoteFiles = context.read<RemoteFileStore>();
    _handledJumpSignal = _remoteFiles!.jumpSignal;
    _remoteFiles!.addListener(_onRemoteFilesChanged);
  }

  @override
  void dispose() {
    _remoteFiles?.removeListener(_onRemoteFilesChanged);
    super.dispose();
  }

  void _onRemoteFilesChanged() {
    final store = _remoteFiles!;
    if (store.jumpSignal == _handledJumpSignal) return;
    _handledJumpSignal = store.jumpSignal;
    setState(() => _selectedIndex = 4);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (i) => setState(() => _selectedIndex = i),
      child: IndexedStack(
        index: _selectedIndex,
        children: const [
          CatalogPage(),
          InventoryPage(),
          SettingsPage(),
          AboutPage(),
          RemoteFilesPage(),
        ],
      ),
    );
  }
}
