import 'package:flutter/material.dart';

ThemeData buildAppTheme({String fontFamily = 'Sarasa Gothic SC'}) {
  return ThemeData(
    colorSchemeSeed: Colors.blue,
    useMaterial3: true,
    fontFamily: fontFamily,
  );
}
