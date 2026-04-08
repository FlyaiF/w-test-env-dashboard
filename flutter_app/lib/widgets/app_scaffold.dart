import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/feature_profile.dart';
import '../sidecar/sidecar_manager.dart';

class _NavGroup {
  final String label;
  final IconData icon;
  final List<_NavItem> items;

  const _NavGroup({
    required this.label,
    required this.icon,
    required this.items,
  });
}

class _NavItem {
  final int index;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Feature? feature; // null = always visible (e.g. settings)

  const _NavItem({
    required this.index,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.feature,
  });
}

const _allGroups = [
  _NavGroup(
    label: '环境',
    icon: Icons.dns_outlined,
    items: [
      _NavItem(
        index: 0,
        label: '总览',
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
        feature: Feature.dashboard,
      ),
      _NavItem(
        index: 1,
        label: '日志',
        icon: Icons.article_outlined,
        selectedIcon: Icons.article,
        feature: Feature.logs,
      ),
      _NavItem(
        index: 2,
        label: '管理',
        icon: Icons.settings_applications_outlined,
        selectedIcon: Icons.settings_applications,
        feature: Feature.management,
      ),
    ],
  ),
  _NavGroup(
    label: '工具',
    icon: Icons.build_outlined,
    items: [
      _NavItem(
        index: 4,
        label: '归档',
        icon: Icons.inventory_2_outlined,
        selectedIcon: Icons.inventory_2,
        feature: Feature.archive,
      ),
    ],
  ),
];

const _settingsItem = _NavItem(
  index: 3,
  label: '设置',
  icon: Icons.settings_outlined,
  selectedIcon: Icons.settings,
);

class AppScaffold extends StatefulWidget {
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
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  bool _expanded = true;
  late Set<int> _expandedGroups;

  static const _expandedWidth = 200.0;
  static const _collapsedWidth = 56.0;
  static const _animDuration = Duration(milliseconds: 200);

  /// Filter nav groups to only include enabled features. Groups with no
  /// remaining items are dropped entirely.
  List<_NavGroup> _visibleGroups(FeatureProfile profile) {
    final result = <_NavGroup>[];
    for (final group in _allGroups) {
      final items = group.items
          .where((i) => i.feature == null || profile.isEnabled(i.feature!))
          .toList();
      if (items.isNotEmpty) {
        result.add(_NavGroup(
          label: group.label,
          icon: group.icon,
          items: items,
        ));
      }
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _expandedGroups = {_activeGroupIndex(_allGroups)};
  }

  @override
  void didUpdateWidget(AppScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _expandedGroups.add(_activeGroupIndex(_allGroups));
      // Auto-collapse when a page is selected
      setState(() => _expanded = false);
    }
  }

  int _activeGroupIndex(List<_NavGroup> groups) {
    for (var gi = 0; gi < groups.length; gi++) {
      if (groups[gi].items.any((item) => item.index == widget.selectedIndex)) {
        return gi;
      }
    }
    return -1; // settings is not in a group
  }

  void _onItemTap(int index) {
    widget.onDestinationSelected(index);
  }

  @override
  Widget build(BuildContext context) {
    final sidecar = context.watch<SidecarManager>();
    final profile = context.watch<FeatureProfile>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final groups = _visibleGroups(profile);

    return Scaffold(
      body: Row(
        children: [
          AnimatedContainer(
            duration: _animDuration,
            curve: Curves.easeInOut,
            width: _expanded ? _expandedWidth : _collapsedWidth,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Use actual width to decide layout, not _expanded flag,
                // so mid-animation frames use the correct layout.
                final showExpanded = constraints.maxWidth >= _expandedWidth;
                return Column(
                  children: [
                    _buildHeader(sidecar, theme, colorScheme, showExpanded),
                    const Divider(height: 1),
                    const SizedBox(height: 4),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        children: [
                          for (var gi = 0; gi < groups.length; gi++) ...[
                            if (gi > 0) const SizedBox(height: 4),
                            _buildGroup(
                              context,
                              groups[gi],
                              gi,
                              colorScheme,
                              showExpanded,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                      child: _buildItem(
                        context, _settingsItem, colorScheme, showExpanded),
                    ),
                  ],
                );
              },
            ),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: widget.child),
        ],
      ),
    );
  }

  Widget _buildHeader(
    SidecarManager sidecar,
    ThemeData theme,
    ColorScheme colorScheme,
    bool showExpanded,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu, size: 20),
            onPressed: () => setState(() => _expanded = !_expanded),
            tooltip: _expanded ? '收起侧栏' : '展开侧栏',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          if (showExpanded) ...[
            const SizedBox(width: 4),
            Icon(
              sidecar.connected ? Icons.cloud_done : Icons.cloud_off,
              color: sidecar.connected ? Colors.green : Colors.red,
              size: 16,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '环境速查',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGroup(
    BuildContext context,
    _NavGroup group,
    int groupIndex,
    ColorScheme colorScheme,
    bool showExpanded,
  ) {
    final isExpanded = _expandedGroups.contains(groupIndex);
    final hasActiveItem =
        group.items.any((item) => item.index == widget.selectedIndex);

    // Collapsed: show items as icon-only, no group header
    if (!showExpanded) {
      return Column(
        children: [
          for (final item in group.items)
            _buildItem(context, item, colorScheme, showExpanded),
        ],
      );
    }

    // Expanded: group header + collapsible items
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Group header
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedGroups.remove(groupIndex);
              } else {
                _expandedGroups.add(groupIndex);
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(
                  group.icon,
                  size: 16,
                  color: hasActiveItem
                      ? colorScheme.primary
                      : colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    group.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          hasActiveItem ? FontWeight.w600 : FontWeight.normal,
                      color: hasActiveItem
                          ? colorScheme.primary
                          : colorScheme.outline,
                    ),
                  ),
                ),
                Icon(
                  isExpanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: colorScheme.outline,
                ),
              ],
            ),
          ),
        ),
        // Items
        if (isExpanded)
          for (final item in group.items)
            _buildItem(context, item, colorScheme, showExpanded),
      ],
    );
  }

  Widget _buildItem(
    BuildContext context,
    _NavItem item,
    ColorScheme colorScheme,
    bool showExpanded,
  ) {
    final isSelected = item.index == widget.selectedIndex;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: isSelected
            ? colorScheme.primaryContainer.withValues(alpha: 0.5)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _onItemTap(item.index),
          child: showExpanded
              ? _expandedItem(item, isSelected, colorScheme)
              : _collapsedItem(item, isSelected, colorScheme),
        ),
      ),
    );
  }

  Widget _expandedItem(
    _NavItem item,
    bool isSelected,
    ColorScheme colorScheme,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: isSelected
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border(
                left: BorderSide(color: colorScheme.primary, width: 3),
              ),
            )
          : null,
      child: Row(
        children: [
          Icon(
            isSelected ? item.selectedIcon : item.icon,
            size: 20,
            color: isSelected
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.label,
              style: TextStyle(
                fontSize: 14,
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _collapsedItem(
    _NavItem item,
    bool isSelected,
    ColorScheme colorScheme,
  ) {
    return Tooltip(
      message: item.label,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 500),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: isSelected
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(color: colorScheme.primary, width: 3),
                ),
              )
            : null,
        child: Icon(
          isSelected ? item.selectedIcon : item.icon,
          size: 20,
          color: isSelected
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
