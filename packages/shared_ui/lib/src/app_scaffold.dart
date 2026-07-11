import 'package:flutter/material.dart';

class NavItem {
  final int index;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const NavItem({
    required this.index,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

class NavGroup {
  final String label;
  final IconData icon;
  final List<NavItem> items;

  const NavGroup({
    required this.label,
    required this.icon,
    required this.items,
  });
}

class AppScaffold extends StatefulWidget {
  final Widget child;
  final List<NavGroup> groups;
  final List<NavItem> footerItems;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final String title;
  final Widget? headerTrailing;

  const AppScaffold({
    super.key,
    required this.child,
    required this.groups,
    required this.footerItems,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.title,
    this.headerTrailing,
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

  @override
  void initState() {
    super.initState();
    _expandedGroups = {_activeGroupIndex()};
  }

  @override
  void didUpdateWidget(AppScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _expandedGroups.add(_activeGroupIndex());
      setState(() => _expanded = false);
    }
  }

  int _activeGroupIndex() {
    for (var gi = 0; gi < widget.groups.length; gi++) {
      if (widget.groups[gi].items.any((item) => item.index == widget.selectedIndex)) {
        return gi;
      }
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
                final showExpanded = constraints.maxWidth >= _expandedWidth;
                return Column(
                  children: [
                    _buildHeader(theme, colorScheme, showExpanded),
                    const Divider(height: 1),
                    const SizedBox(height: 4),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        children: [
                          for (var gi = 0; gi < widget.groups.length; gi++) ...[
                            if (gi > 0) const SizedBox(height: 4),
                            _buildGroup(
                              context,
                              widget.groups[gi],
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
                      child: Column(
                        children: [
                          for (final item in widget.footerItems)
                            _buildItem(context, item, colorScheme, showExpanded),
                        ],
                      ),
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
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          if (showExpanded) ...[
            const SizedBox(width: 4),
            if (widget.headerTrailing != null) ...[
              widget.headerTrailing!,
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                widget.title,
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
    NavGroup group,
    int groupIndex,
    ColorScheme colorScheme,
    bool showExpanded,
  ) {
    final isExpanded = _expandedGroups.contains(groupIndex);
    final hasActiveItem =
        group.items.any((item) => item.index == widget.selectedIndex);

    if (!showExpanded) {
      return Column(
        children: [
          for (final item in group.items)
            _buildItem(context, item, colorScheme, showExpanded),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        if (isExpanded)
          for (final item in group.items)
            _buildItem(context, item, colorScheme, showExpanded),
      ],
    );
  }

  Widget _buildItem(
    BuildContext context,
    NavItem item,
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
          onTap: () => widget.onDestinationSelected(item.index),
          child: showExpanded
              ? _expandedItem(item, isSelected, colorScheme)
              : _collapsedItem(item, isSelected, colorScheme),
        ),
      ),
    );
  }

  Widget _expandedItem(
    NavItem item,
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
    NavItem item,
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
