import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// UI preferences persisted at `~/.test-env-dashboard/ui.json`: theme mode and
/// the sidebar's manual expand/collapse state. This controller is the single
/// writer of ui.json so keys never clobber each other.
class AppThemeController extends ChangeNotifier {
  static const _dirName = '.test-env-dashboard';
  static const _fileName = 'ui.json';
  static const _themeModeKey = 'theme_mode';
  static const _sidebarExpandedKey = 'sidebar_expanded';

  ThemeMode _themeMode = ThemeMode.system;
  bool _sidebarExpanded = true;
  bool _loaded = false;

  ThemeMode get themeMode => _themeMode;
  bool get sidebarExpanded => _sidebarExpanded;
  bool get loaded => _loaded;

  Future<void> load() async {
    try {
      final file = await _settingsFile(createDirectory: false);
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content);
        if (data is Map<String, dynamic>) {
          _themeMode = _themeModeFromStorage(data[_themeModeKey]);
          _sidebarExpanded = data[_sidebarExpandedKey] != false;
        }
      }
    } catch (e) {
      debugPrint('AppThemeController.load error: $e');
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode && _loaded) return;
    _themeMode = mode;
    _loaded = true;
    notifyListeners();
    await _save();
  }

  Future<void> setSidebarExpanded(bool expanded) async {
    if (_sidebarExpanded == expanded) return;
    _sidebarExpanded = expanded;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = await _settingsFile(createDirectory: true);
      const encoder = JsonEncoder.withIndent('  ');
      await file.writeAsString(
        encoder.convert({
          _themeModeKey: _themeModeToStorage(_themeMode),
          _sidebarExpandedKey: _sidebarExpanded,
        }),
      );
    } catch (e) {
      debugPrint('AppThemeController.save error: $e');
    }
  }

  static Future<File> _settingsFile({required bool createDirectory}) async {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    final dir = Directory('$home/$_dirName');
    if (createDirectory && !await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/$_fileName');
  }

  static ThemeMode _themeModeFromStorage(dynamic value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static String _themeModeToStorage(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
  }
}

class ThemeModeSelector extends StatelessWidget {
  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  const ThemeModeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ThemeMode>(
      selected: {value},
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: ThemeMode.system,
          icon: Icon(Icons.brightness_auto_outlined),
          label: Text('跟随系统'),
        ),
        ButtonSegment(
          value: ThemeMode.light,
          icon: Icon(Icons.light_mode_outlined),
          label: Text('浅色'),
        ),
        ButtonSegment(
          value: ThemeMode.dark,
          icon: Icon(Icons.dark_mode_outlined),
          label: Text('深色'),
        ),
      ],
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}
