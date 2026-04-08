import 'dart:io';

import 'package:flutter/foundation.dart';

enum Feature { dashboard, logs, management, archive }

class FeatureProfile extends ChangeNotifier {
  /// Executable-name → enabled features. Unmatched names get all features.
  static const _profiles = <String, Set<Feature>>{
    'env_viewer': {Feature.dashboard, Feature.logs, Feature.management},
    'zipr_tool': {Feature.archive},
  };

  static final FeatureProfile _instance = FeatureProfile._();
  factory FeatureProfile() => _instance;

  late Set<Feature> _profileFeatures;
  bool _showAll = false;

  FeatureProfile._() {
    _profileFeatures = _resolve();
  }

  /// Whether the executable name matched a named profile (not the default).
  bool get isNamedProfile => _profileFeatures.length != Feature.values.length;

  bool get showAll => _showAll;
  set showAll(bool value) {
    if (_showAll != value) {
      _showAll = value;
      notifyListeners();
    }
  }

  Set<Feature> get enabledFeatures =>
      _showAll ? Feature.values.toSet() : _profileFeatures;

  bool isEnabled(Feature feature) => enabledFeatures.contains(feature);

  static Set<Feature> _resolve() {
    final exe = Platform.resolvedExecutable;
    // Extract the filename without path.
    var name = exe.split(Platform.pathSeparator).last;
    // Strip .exe on Windows.
    if (name.toLowerCase().endsWith('.exe')) {
      name = name.substring(0, name.length - 4);
    }

    // macOS bundle: /Foo.app/Contents/MacOS/foo — use the .app folder name.
    if (Platform.isMacOS) {
      final segments = exe.split('/');
      final appIdx = segments.indexWhere((s) => s.endsWith('.app'));
      if (appIdx >= 0) {
        final appName = segments[appIdx];
        name = appName.substring(0, appName.length - 4); // strip .app
      }
    }

    name = name.toLowerCase();

    for (final entry in _profiles.entries) {
      if (name == entry.key || name.startsWith('${entry.key}_')) {
        return entry.value;
      }
    }
    return Feature.values.toSet(); // default: all features
  }
}
