import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'config/config_service.dart';
import 'sidecar/sidecar_manager.dart';
import 'sidecar/sidecar_client.dart';
import 'services/env_service.dart';
import 'widgets/app_scaffold.dart';
import 'pages/dashboard/dashboard_page.dart';
import 'pages/log_viewer/log_viewer_page.dart';
import 'pages/management/management_page.dart';
import 'pages/settings/settings_page.dart';

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

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SidecarManager()),
        ChangeNotifierProvider(create: (_) => EnvService()),
      ],
      child: MaterialApp(
        title: '测试环境速查工具',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.blue,
          useMaterial3: true,
        ),
        home: const HomePage(),
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

    final sidecar = context.read<SidecarManager>();
    final envService = context.read<EnvService>();

    if (config.isOracleConfigured) {
      await sidecar.start(config.dsn);
      if (sidecar.connected) {
        envService.setClient(SidecarClient(sidecar.baseUrl));
      }
    }

    sidecar.addListener(() {
      if (sidecar.connected && sidecar.port != null) {
        envService.setClient(SidecarClient(sidecar.baseUrl));
      }
    });

    setState(() => _initialized = true);

    if (!config.isOracleConfigured) {
      setState(() => _selectedIndex = 3);
    }
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
          DashboardPage(onViewLog: (env) {
            setState(() => _selectedIndex = 1);
            _logViewerKey.currentState?.connectToEnv(env);
          }),
          LogViewerPage(key: _logViewerKey),
          const ManagementPage(),
          const SettingsPage(),
        ],
      ),
    );
  }
}
