import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_ui/shared_ui.dart' as ui;

import '../config/feature_profile.dart';
import '../sidecar/sidecar_manager.dart';

class _ItemSpec {
  final ui.NavItem item;
  final Feature? feature; // null = always visible
  const _ItemSpec(this.item, this.feature);
}

class _GroupSpec {
  final String label;
  final IconData icon;
  final List<_ItemSpec> items;
  const _GroupSpec({required this.label, required this.icon, required this.items});
}

const _allGroups = [
  _GroupSpec(
    label: '环境',
    icon: Icons.dns_outlined,
    items: [
      _ItemSpec(
        ui.NavItem(
          index: 0,
          label: '总览',
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard,
        ),
        Feature.dashboard,
      ),
      _ItemSpec(
        ui.NavItem(
          index: 1,
          label: '日志',
          icon: Icons.article_outlined,
          selectedIcon: Icons.article,
        ),
        Feature.logs,
      ),
      _ItemSpec(
        ui.NavItem(
          index: 2,
          label: '管理',
          icon: Icons.settings_applications_outlined,
          selectedIcon: Icons.settings_applications,
        ),
        Feature.management,
      ),
    ],
  ),
  _GroupSpec(
    label: '工具',
    icon: Icons.build_outlined,
    items: [
      _ItemSpec(
        ui.NavItem(
          index: 4,
          label: '归档',
          icon: Icons.inventory_2_outlined,
          selectedIcon: Icons.inventory_2,
        ),
        Feature.archive,
      ),
    ],
  ),
];

const _settingsItem = _ItemSpec(
  ui.NavItem(
    index: 3,
    label: '设置',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
  ),
  null,
);

const _aboutItem = _ItemSpec(
  ui.NavItem(
    index: 5,
    label: '关于',
    icon: Icons.info_outline,
    selectedIcon: Icons.info,
  ),
  Feature.about,
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
    final profile = context.watch<FeatureProfile>();

    final groups = <ui.NavGroup>[];
    for (final g in _allGroups) {
      final items = g.items
          .where((s) => s.feature == null || profile.isEnabled(s.feature!))
          .map((s) => s.item)
          .toList();
      if (items.isNotEmpty) {
        groups.add(ui.NavGroup(label: g.label, icon: g.icon, items: items));
      }
    }

    final footer = <ui.NavItem>[
      if (profile.isEnabled(Feature.about)) _aboutItem.item,
      _settingsItem.item,
    ];

    return ui.AppScaffold(
      groups: groups,
      footerItems: footer,
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
