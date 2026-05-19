import 'package:flutter/material.dart';

ThemeData buildAppTheme({
  String fontFamily = 'Sarasa Gothic SC',
  Brightness brightness = Brightness.light,
}) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: Colors.blue,
    brightness: brightness,
  );

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    fontFamily: fontFamily,
  );
}
