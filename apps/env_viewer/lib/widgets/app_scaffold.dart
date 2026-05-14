import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart' as ui;

import '../sidecar/sidecar_manager.dart';

const _envGroup = ui.NavGroup(
  label: '环境',
  icon: Icons.dns_outlined,
  items: [
    ui.NavItem(
      index: 0,
      label: '总览',
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard,
    ),
    ui.NavItem(
      index: 1,
      label: '日志',
      icon: Icons.article_outlined,
      selectedIcon: Icons.article,
    ),
    ui.NavItem(
      index: 2,
      label: '管理',
      icon: Icons.settings_applications_outlined,
      selectedIcon: Icons.settings_applications,
    ),
  ],
);

const _aboutItem = ui.NavItem(
  index: 4,
  label: '关于',
  icon: Icons.info_outline,
  selectedIcon: Icons.info,
);

const _settingsItem = ui.NavItem(
  index: 3,
  label: '设置',
  icon: Icons.settings_outlined,
  selectedIcon: Icons.settings,
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
    final sidecar = context.watch<SidecarManager>();

    return ui.AppScaffold(
      groups: const [_envGroup],
      footerItems: const [_aboutItem, _settingsItem],
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      title: '环境速查',
      headerTrailing: Icon(
        sidecar.connected ? Icons.cloud_done : Icons.cloud_off,
        color: sidecar.connected ? Colors.green : Colors.red,
        size: 16,
      ),
      child: child,
    );
  }
}
