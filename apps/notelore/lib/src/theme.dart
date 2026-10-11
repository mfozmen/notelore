/// The app's look: flat and calm, teal, light and dark following the system.
///
/// From the ui-ux-pro-max skill's design system for a productivity tool: flat
/// surfaces (outlines instead of shadows), one teal accent, an 8-point spacing
/// rhythm, at least 48-point tap targets and rounded, friendly shapes.
library;

import 'package:flutter/material.dart';

const _teal = Color(0xFF0D9488);

/// The spacing steps every screen uses.
abstract final class Gap {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 16;
  static const double l = 24;
}

ThemeData noteloreTheme(Brightness brightness) {
  final colors = ColorScheme.fromSeed(seedColor: _teal, brightness: brightness);
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  const tap = Size(48, 48);
  return ThemeData(
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
    ),
    listTileTheme: ListTileThemeData(shape: rounded, minVerticalPadding: Gap.s),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      // The focused field stays visible for keyboard users.
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: tap, shape: const StadiumBorder()),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: tap, shape: const StadiumBorder()),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: tap)),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: tap)),
    chipTheme: ChipThemeData(
      shape: StadiumBorder(side: BorderSide(color: colors.outlineVariant)),
      backgroundColor: colors.surfaceContainerLow,
    ),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: rounded),
    bannerTheme: MaterialBannerThemeData(backgroundColor: colors.secondaryContainer),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      backgroundColor: colors.surfaceContainer,
      indicatorColor: colors.secondaryContainer,
    ),
    dividerTheme: DividerThemeData(color: colors.outlineVariant, space: 1),
  );
}
