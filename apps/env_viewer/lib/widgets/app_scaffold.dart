import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart' as ui;

import '../catalog/environment_store.dart';

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
  ],
);

const _aboutItem = ui.NavItem(
  index: 1,
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

    return ui.AppScaffold(
      groups: const [_envGroup],
      footerItems: const [_aboutItem],
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      title: '环境速查',
      headerTrailing: Icon(
        connected ? Icons.cloud_done : Icons.cloud_off,
        color: connected ? Colors.green : Colors.red,
        size: 16,
      ),
      child: child,
    );
  }
}
