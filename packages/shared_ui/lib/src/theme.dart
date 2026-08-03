import 'package:flutter/material.dart';

/// Design tokens for the approved 方向 D visual identity: warm-graphite console
/// ground, one teal accent reserved for interaction/selection, and a strict
/// green/amber/red status language. All machine data (versions, hosts, ports,
/// addresses, timestamps) renders in [monoFontFamily]; UI text in the theme's
/// default family. Light and dark are both first-class.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  final Color bg;
  final Color sidebarBg;
  final Color rosterBg;
  final Color cardBg;
  final Color cardBodyBg;
  final Color tableHeaderBg;
  final Color text;
  final Color textSecondary;
  final Color border;
  final Color borderSoft;
  final Color cardBorder;
  final Color hover;
  final Color selectionBg;
  final Color selectionBorder;
  final Color accent;
  final Color onAccent;
  final Color ok;
  final Color okBg;

  /// Amber, reserved for staleness (⚠ data older than the freshness window).
  final Color warn;
  final Color err;
  final Color errBg;
  final Color neutralChipBg;

  const AppTokens({
    required this.bg,
    required this.sidebarBg,
    required this.rosterBg,
    required this.cardBg,
    required this.cardBodyBg,
    required this.tableHeaderBg,
    required this.text,
    required this.textSecondary,
    required this.border,
    required this.borderSoft,
    required this.cardBorder,
    required this.hover,
    required this.selectionBg,
    required this.selectionBorder,
    required this.accent,
    required this.onAccent,
    required this.ok,
    required this.okBg,
    required this.warn,
    required this.err,
    required this.errBg,
    required this.neutralChipBg,
  });

  /// Monospace family for machine data. A token (not a hardcode) so a future
  /// font swap happens in exactly one place.
  static const String monoFontFamily = 'Sarasa Mono SC';

  /// Radius scale: controls 6, list rows 9, cards 8, chips 4.
  static const double radiusControl = 6;
  static const double radiusRow = 9;
  static const double radiusCard = 8;
  static const double radiusChip = 4;

  static const AppTokens light = AppTokens(
    bg: Color(0xFFF4F4F1),
    sidebarBg: Color(0xFFECECE8),
    rosterBg: Color(0xFFF0F0EC),
    cardBg: Color(0xFFFBFBF9),
    cardBodyBg: Color(0xFFF6F6F3),
    tableHeaderBg: Color(0xFFF1F1ED),
    text: Color(0xFF26282A),
    textSecondary: Color(0xFF71757A),
    border: Color(0xFFD3D3CC),
    borderSoft: Color(0xFFE2E2DB),
    cardBorder: Color(0xFFDBDBD4),
    hover: Color(0xFFE9E9E4),
    selectionBg: Color(0xFFDBEAE8),
    selectionBorder: Color(0xFFC4DBD8),
    accent: Color(0xFF1F7A76),
    onAccent: Color(0xFFFFFFFF),
    ok: Color(0xFF2E7D4F),
    okBg: Color(0xFFE4EFE7),
    warn: Color(0xFFA56D0A),
    err: Color(0xFFB4402C),
    errBg: Color(0xFFF5E4E0),
    neutralChipBg: Color(0xFFEAEAE5),
  );

  static const AppTokens dark = AppTokens(
    bg: Color(0xFF17181A),
    sidebarBg: Color(0xFF131416),
    rosterBg: Color(0xFF151618),
    cardBg: Color(0xFF1E2023),
    cardBodyBg: Color(0xFF1A1C1E),
    tableHeaderBg: Color(0xFF1B1D20),
    text: Color(0xFFDCDEE0),
    textSecondary: Color(0xFF8B9095),
    border: Color(0xFF303337),
    borderSoft: Color(0xFF26292C),
    cardBorder: Color(0xFF2C2F33),
    hover: Color(0xFF232528),
    selectionBg: Color(0xFF20312F),
    selectionBorder: Color(0xFF2E4A47),
    accent: Color(0xFF59B3AD),
    onAccent: Color(0xFF10201F),
    ok: Color(0xFF5CB380),
    okBg: Color(0xFF1D2B22),
    warn: Color(0xFFD2A24A),
    err: Color(0xFFDF6E58),
    errBg: Color(0xFF33211D),
    neutralChipBg: Color(0xFF232528),
  );

  static AppTokens of(BuildContext context) =>
      Theme.of(context).extension<AppTokens>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  /// Machine-data text style (mono), sized for dense rows.
  TextStyle mono({double fontSize = 13, Color? color, FontWeight? weight}) =>
      TextStyle(
        fontFamily: monoFontFamily,
        fontSize: fontSize,
        color: color ?? text,
        fontWeight: weight,
      );

  @override
  AppTokens copyWith() => this;

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppTokens(
      bg: mix(bg, other.bg),
      sidebarBg: mix(sidebarBg, other.sidebarBg),
      rosterBg: mix(rosterBg, other.rosterBg),
      cardBg: mix(cardBg, other.cardBg),
      cardBodyBg: mix(cardBodyBg, other.cardBodyBg),
      tableHeaderBg: mix(tableHeaderBg, other.tableHeaderBg),
      text: mix(text, other.text),
      textSecondary: mix(textSecondary, other.textSecondary),
      border: mix(border, other.border),
      borderSoft: mix(borderSoft, other.borderSoft),
      cardBorder: mix(cardBorder, other.cardBorder),
      hover: mix(hover, other.hover),
      selectionBg: mix(selectionBg, other.selectionBg),
      selectionBorder: mix(selectionBorder, other.selectionBorder),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      ok: mix(ok, other.ok),
      okBg: mix(okBg, other.okBg),
      warn: mix(warn, other.warn),
      err: mix(err, other.err),
      errBg: mix(errBg, other.errBg),
      neutralChipBg: mix(neutralChipBg, other.neutralChipBg),
    );
  }
}

ThemeData buildAppTheme({
  String fontFamily = 'Sarasa Gothic SC',
  Brightness brightness = Brightness.light,
}) {
  final tokens = brightness == Brightness.dark
      ? AppTokens.dark
      : AppTokens.light;
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: tokens.accent,
        brightness: brightness,
      ).copyWith(
        primary: tokens.accent,
        onPrimary: tokens.onAccent,
        primaryContainer: tokens.selectionBg,
        onPrimaryContainer: tokens.accent,
        surface: tokens.bg,
        onSurface: tokens.text,
        onSurfaceVariant: tokens.textSecondary,
        surfaceContainerLowest: tokens.cardBodyBg,
        surfaceContainerLow: tokens.sidebarBg,
        surfaceContainer: tokens.cardBg,
        surfaceContainerHigh: tokens.hover,
        surfaceContainerHighest: tokens.neutralChipBg,
        error: tokens.err,
        errorContainer: tokens.errBg,
        onErrorContainer: tokens.err,
        outline: tokens.textSecondary,
        outlineVariant: tokens.borderSoft,
      );

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    fontFamily: fontFamily,
    scaffoldBackgroundColor: tokens.bg,
    canvasColor: tokens.cardBg,
    dividerTheme: DividerThemeData(color: tokens.borderSoft),
    cardTheme: CardThemeData(
      color: tokens.cardBg,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        side: BorderSide(color: tokens.cardBorder),
      ),
    ),
    dialogTheme: DialogThemeData(backgroundColor: tokens.cardBg),
    popupMenuTheme: PopupMenuThemeData(color: tokens.cardBg),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
    ),
    extensions: [tokens],
  );
}
