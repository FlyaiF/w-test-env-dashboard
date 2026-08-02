import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart' as ui;

import '../catalog/environment_store.dart';
import 'update_button.dart';

const _envGroup = ui.NavGroup(
  label: '环境',
  icon: Icons.dns_outlined,
  items: [
    ui.NavItem(
      index: 0,
      label: '环境目录',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
    ),
    ui.NavItem(
      index: 1,
      label: '资源清单',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2,
    ),
    // Index 4: pages 2/3 predate this page and keep their footer indices.
    ui.NavItem(
      index: 4,
      label: '日志文件',
      icon: Icons.article_outlined,
      selectedIcon: Icons.article,
    ),
  ],
);

const _settingsItem = ui.NavItem(
  index: 2,
  label: '设置',
  icon: Icons.settings_outlined,
  selectedIcon: Icons.settings,
);

const _aboutItem = ui.NavItem(
  index: 3,
  label: '关于',
  icon: Icons.info_outline,
  selectedIcon: Icons.info,
);

class AppScaffold extends StatelessWidget {
  final Widget child;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const AppScaffold({
    super.key,
    required this.child,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final connected = context.select<EnvironmentStore, bool>(
      (s) => s.connected,
    );
    final themeController = context.watch<ui.AppThemeController>();
    final tokens = ui.AppTokens.of(context);

    return ui.AppScaffold(
      groups: const [_envGroup],
      footerItems: const [_settingsItem, _aboutItem],
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      title: '环境速查',
      sidebarExpanded: themeController.sidebarExpanded,
      onSidebarToggle: themeController.setSidebarExpanded,
      // Wrap, not Row: in the collapsed rail this sits in ~44px of width and
      // must fold the indicators vertically instead of overflowing.
      headerTrailing: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 6,
        children: [
          const UpdateButton(),
          Icon(
            connected ? Icons.cloud_done : Icons.cloud_off,
            color: connected ? tokens.ok : tokens.err,
            size: 16,
          ),
        ],
      ),
      child: child,
    );
  }
}
