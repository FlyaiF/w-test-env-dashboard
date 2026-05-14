import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:window_manager/window_manager.dart';
import 'pages/archive_tool/archive_tool_page.dart';
import 'pages/about/about_page.dart';
import 'services/zipr_service.dart';
import 'src/rust/frb_generated.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();

  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(900, 600),
    center: true,
    title: '归档差异与补丁工具',
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
        ChangeNotifierProvider(create: (_) => ZiprService()),
      ],
      child: MaterialApp(
        title: '归档差异与补丁工具',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const HomePage(),
      ),
    );
  }
}

const _archiveItem = NavItem(
  index: 0,
  label: '归档',
  icon: Icons.inventory_2_outlined,
  selectedIcon: Icons.inventory_2,
);

const _aboutItem = NavItem(
  index: 1,
  label: '关于',
  icon: Icons.info_outline,
  selectedIcon: Icons.info,
);

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
      groups: const [
        NavGroup(
          label: '工具',
          icon: Icons.build_outlined,
          items: [_archiveItem],
        ),
      ],
      footerItems: const [_aboutItem],
      selectedIndex: _selectedIndex,
      onDestinationSelected: (i) => setState(() => _selectedIndex = i),
      title: '归档工具',
      child: IndexedStack(
        index: _selectedIndex,
        children: const [
          ArchiveToolPage(),
          AboutPage(),
        ],
      ),
    );
  }
}
