import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'config/config_service.dart';
import 'config/feature_profile.dart';
import 'sidecar/sidecar_manager.dart';
import 'sidecar/sidecar_client.dart';
import 'services/env_service.dart';
import 'services/local_store.dart';
import 'services/zipr_service.dart';
import 'widgets/app_scaffold.dart';
import 'pages/dashboard/dashboard_page.dart';
import 'pages/log_viewer/log_viewer_page.dart';
import 'pages/management/management_page.dart';
import 'pages/settings/settings_page.dart';
import 'pages/archive_tool/archive_tool_page.dart';
import 'pages/about/about_page.dart';
import 'services/log_file_store.dart';
import 'src/rust/frb_generated.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final profile = FeatureProfile();
  if (profile.isEnabled(Feature.archive)) {
    await RustLib.init();
  }
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
        ChangeNotifierProvider.value(value: FeatureProfile()),
        ChangeNotifierProvider(create: (_) => SidecarManager()),
        ChangeNotifierProvider(create: (_) => LocalStore()),
        ChangeNotifierProvider(create: (_) => EnvService()),
        ChangeNotifierProvider(create: (_) => ZiprService()),
      ],
      child: MaterialApp(
        title: '测试环境速查工具',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.blue,
          useMaterial3: true,
          fontFamily: 'Sarasa Gothic SC',
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

/// Maps page indices to their required feature.
class _PageEntry {
  final int index;
  final Feature feature;
  const _PageEntry(this.index, this.feature);
}

const _pageEntries = [
  _PageEntry(0, Feature.dashboard),
  _PageEntry(1, Feature.logs),
  _PageEntry(2, Feature.management),
  // index 3 = settings, always visible
  _PageEntry(4, Feature.archive),
  _PageEntry(5, Feature.about),
];

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

    final profile = context.read<FeatureProfile>();
    profile.showAll = config.showAllFeatures;

    final hasEnv = profile.isEnabled(Feature.dashboard);

    if (hasEnv) {
      final sidecar = context.read<SidecarManager>();
      final envService = context.read<EnvService>();
      final localStore = context.read<LocalStore>();

      // Load local data first (local-first).
      await localStore.load();
      envService.setLocalStore(localStore);
      await envService.load();

      if (config.isOracleConfigured) {
        await sidecar.start(config.dsn);
        if (sidecar.connected) {
          envService.setClient(SidecarClient(sidecar.baseUrl));
          // Auto-sync from remote on connect.
          envService.sync();
        }
      }

      sidecar.addListener(() {
        if (sidecar.connected && sidecar.port != null) {
          envService.setClient(SidecarClient(sidecar.baseUrl));
          // Auto-sync when sidecar reconnects.
          envService.sync();
        }
      });
    }

    setState(() => _initialized = true);

    // Pick a valid default page for the active profile.
    if (hasEnv && !config.isOracleConfigured) {
      setState(() => _selectedIndex = 3); // settings
    } else if (!hasEnv) {
      // First enabled page.
      setState(() => _selectedIndex = _pageEntries
          .firstWhere((e) => profile.isEnabled(e.feature))
          .index);
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
          const ArchiveToolPage(),
          const AboutPage(),
        ],
      ),
    );
  }
}
