/// The app's look: flat and calm, in a nature palette, light or dark.
///
/// From the ui-ux-pro-max skill's design system for a productivity tool: flat
/// surfaces (outlines instead of shadows), one teal accent, an 8-point spacing
/// rhythm, at least 48-point tap targets and rounded, friendly shapes.
library;

import 'package:flutter/material.dart';

/// Colour palettes taken from landscapes. Each seeds a light and a dark
/// scheme, so Material 3 keeps the contrast right in both.
enum Palette {
  lagoon(Color(0xFF0D9488)), // shallow water over sand
  forest(Color(0xFF15803D)), // pine needles and moss
  sea(Color(0xFF0369A1)), // open water far from shore
  sunset(Color(0xFFEA580C)), // the sky as the sun goes down
  lavender(Color(0xFF7C3AED)), // a lavender field in summer
  aurora(Color(0xFF4F46E5)); // a northern night sky

  const Palette(this.seed);

  final Color seed;
}

/// Light, dark, or whatever the device uses.
enum Appearance {
  system(ThemeMode.system),
  light(ThemeMode.light),
  dark(ThemeMode.dark);

  const Appearance(this.mode);

  final ThemeMode mode;
}

/// Corner radii: cards and tiles, and the rounder input fields.
const _card = 16.0;
const _field = 24.0;
const _control = 12.0;

/// The spacing steps every screen uses.
abstract final class Gap {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 16;
  static const double l = 24;
}

/// How an answer's Markdown is drawn on its bubble (#335). The tints are of the
/// bubble's own text colour, so they read in every palette, light and dark.
abstract final class AnswerStyle {
  /// As bold words: an answer keeps to two weights.
  static const headingWeight = FontWeight.bold;

  /// Behind code, inline and in a block.
  static const double tint = 0.12;

  /// A quote's bar at its left.
  static const double quoteBar = 0.4;
  static const double quoteBarWidth = 3;
}

/// The sizes the screens lay out by.
abstract final class Layout {
  /// From this window width the app is laid out for a desk: a side rail, and
  /// panes side by side. The screens all go by the window, so they switch together.
  static const double wide = 840;

  /// From this window width the rail shows its labels.
  static const double roomy = 1200;

  /// The widest a column of text or cards gets.
  static const double column = 760;

  /// The widest the conversation gets.
  static const double chat = 840;

  static bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= wide;
}

ThemeData noteloreTheme(Brightness brightness, [Palette palette = Palette.lagoon]) {
  final colors = ColorScheme.fromSeed(seedColor: palette.seed, brightness: brightness);
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(_card));
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
        borderRadius: BorderRadius.circular(_card),
        side: BorderSide(color: colors.outlineVariant),
      ),
    ),
    listTileTheme: ListTileThemeData(shape: rounded, minVerticalPadding: Gap.s),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_field),
        borderSide: BorderSide.none,
      ),
      // The focused field stays visible for keyboard users.
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_field),
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
    // The desktop side rail: a sidebar tone (its labels are sized in Home).
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colors.surfaceContainer,
      indicatorColor: colors.secondaryContainer,
    ),
    // Every picker: a filled, rounded field and a rounded menu above the page.
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_control),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_control),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
      ),
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerHigh),
        elevation: const WidgetStatePropertyAll(3),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(_control)),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: Gap.xs)),
      ),
    ),
    dividerTheme: DividerThemeData(color: colors.outlineVariant, space: 1),
  );
}
