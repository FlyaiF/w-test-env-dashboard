import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart'
    show AppThemeController, buildAppTheme;
import 'package:window_manager/window_manager.dart';
import 'config/config_service.dart';
import 'sidecar/sidecar_manager.dart';
import 'sidecar/sidecar_client.dart';
import 'services/env_service.dart';
import 'services/local_store.dart';
import 'widgets/app_scaffold.dart';
import 'pages/dashboard/dashboard_page.dart';
import 'pages/log_viewer/log_viewer_page.dart';
import 'pages/management/management_page.dart';
import 'pages/settings/settings_page.dart';
import 'pages/about/about_page.dart';
import 'services/log_file_store.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await LogFileStore.cleanOrphans();

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

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppThemeController()..load()),
        ChangeNotifierProvider(create: (_) => SidecarManager()),
        ChangeNotifierProvider(create: (_) => LocalStore()),
        ChangeNotifierProvider(create: (_) => EnvService()),
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

class _HomePageState extends State<HomePage> with WindowListener {
  int _selectedIndex = 0;
  bool _initialized = false;
  bool _envReady = false;
  final _logViewerKey = GlobalKey<LogViewerPageState>();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initApp();
  }

  Future<void> _initApp() async {
    final config = await ConfigService.load();
    if (!mounted) return;

    await _ensureEnvReady(config: config);

    if (!mounted) return;
    setState(() => _initialized = true);

    if (!config.isOracleConfigured) {
      setState(() => _selectedIndex = 3); // settings
    }
  }

  Future<void> _ensureEnvReady({AppConfig? config}) async {
    if (_envReady) return;
    _envReady = true;

    final cfg = config ?? await ConfigService.load();
    if (!mounted) return;

    final sidecar = context.read<SidecarManager>();
    final envService = context.read<EnvService>();
    final localStore = context.read<LocalStore>();

    await localStore.load();
    envService.setLocalStore(localStore);
    await envService.load();

    if (cfg.isOracleConfigured) {
      await sidecar.start(cfg.dsn);
      if (sidecar.connected) {
        envService.setClient(SidecarClient(sidecar.baseUrl));
        envService.sync();
      }
    }

    sidecar.addListener(() {
      if (sidecar.connected && sidecar.port != null) {
        envService.setClient(SidecarClient(sidecar.baseUrl));
        envService.sync();
      }
    });
  }

  @override
  void onWindowClose() async {
    final sidecar = context.read<SidecarManager>();
    await sidecar.stop();
    await windowManager.destroy();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在启动...'),
            ],
          ),
        ),
      );
    }

    return AppScaffold(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (i) => setState(() => _selectedIndex = i),
      child: IndexedStack(
        index: _selectedIndex,
        children: [
          DashboardPage(
            onViewLog: (env) {
              setState(() => _selectedIndex = 1);
              _logViewerKey.currentState?.connectToEnv(env);
            },
          ),
          LogViewerPage(key: _logViewerKey),
          const ManagementPage(),
          const SettingsPage(),
          const AboutPage(),
        ],
      ),
    );
  }
}
