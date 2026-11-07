/// The app's look: Kil (clay) by day, Orman (forest) by night, from the
/// approved mockup in `docs/design/kil-orman/`.
///
/// Flat surfaces with outlines, one warm accent, Fraunces titles over Plus
/// Jakarta Sans, an 8-point spacing rhythm and at least 48-point tap targets.
library;

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'icons.dart';
import 'schemes.dart';

/// Light, dark, or whatever the device uses.
enum Appearance {
  system(ThemeMode.system),
  light(ThemeMode.light),
  dark(ThemeMode.dark);

  const Appearance(this.mode);

  final ThemeMode mode;
}

/// Corner radii: cards and tiles, and the rounder input fields.
const _card = 18.0;
const _field = 28.0;
const _control = 12.0;

/// The spacing steps every screen uses.
abstract final class Gap {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 16;
  static const double l = 24;
}

/// How an answer's Markdown is drawn on its bubble (#335). The tints are of the
/// bubble's own text colour, so they read in both themes.
abstract final class AnswerStyle {
  /// As bold words: an answer keeps to two weights.
  static const headingWeight = FontWeight.bold;

  /// Behind code, inline and in a block.
  static const double tint = 0.12;

  /// A quote's bar at its left.
  static const double quoteBar = 0.4;
  static const double quoteBarWidth = 3;
}

/// Rounded, with a smaller corner on the speaker's side, like a speech bubble:
/// the person's on the right ([mine]), the model's on the left.
BorderRadius bubbleRadius({required bool mine}) => BorderRadius.only(
  topLeft: const Radius.circular(18),
  topRight: const Radius.circular(18),
  bottomLeft: Radius.circular(mine ? 18 : 4),
  bottomRight: Radius.circular(mine ? 4 : 18),
);

/// The sizes the screens lay out by.
abstract final class Layout {
  /// From this window width the app is laid out for a desk: a side rail, and
  /// panes side by side. The screens all go by the window, so they switch together.
  static const double wide = 840;

  /// From this window width the rail shows its labels.
  static const double roomy = 1200;

  /// The widest a column of text or cards gets.
  static const double column = 760;

  /// The widest the conversation gets; a wide window uses it instead of a
  /// narrow column in the middle.
  static const double chat = 1400;

  /// About this many characters on a bubble's line, whatever the text size.
  static const int bubbleCharacters = 90;

  /// The widest a speech bubble gets in [width]: a gutter on the other side
  /// on a phone, a readable line on a wide window. Measured in characters, so
  /// bigger text gets a wider bubble rather than more wrapping.
  static double bubbleFor(BuildContext context, double width) {
    final style = Theme.of(context).textTheme.bodyMedium ?? const TextStyle(fontSize: 14);
    final painter = TextPainter(
      text: TextSpan(text: 'n' * bubbleCharacters, style: style),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
    )..layout();
    final ideal = painter.width + 2 * Gap.m;
    painter.dispose();
    return min(ideal, width * 0.85);
  }

  /// A fixed cap for the places that do not scale their text (setup, about me).
  static double bubble(double width) => min(560, width * 0.85);

  static bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= wide;
}

/// The look's colours a [ColorScheme] has no role for. Screens read them with
/// `Theme.of(context).extension<NoteloreTokens>()!`.
@immutable
class NoteloreTokens extends ThemeExtension<NoteloreTokens> {
  const NoteloreTokens({
    required this.hot,
    required this.hotText,
    required this.hotValue,
    required this.hotBorder,
    required this.glow,
    required this.mineBorder,
    required this.bright,
    required this.label,
  });

  /// The current decision's card: its fill, its words, its value and its edge.
  final LinearGradient hot;
  final Color hotText;
  final Color hotValue;
  final Color hotBorder;

  /// The glow at the top of the screen at night; none by day.
  final RadialGradient? glow;

  /// The edge of the person's own message.
  final Color mineBorder;

  /// The accent at its brightest, for fills behind no text (the mic).
  final Color bright;

  /// Small mono section labels; the widget puts them in capitals.
  final TextStyle label;

  @override
  NoteloreTokens copyWith({
    LinearGradient? hot,
    Color? hotText,
    Color? hotValue,
    Color? hotBorder,
    RadialGradient? glow,
    Color? mineBorder,
    Color? bright,
    TextStyle? label,
  }) => NoteloreTokens(
    hot: hot ?? this.hot,
    hotText: hotText ?? this.hotText,
    hotValue: hotValue ?? this.hotValue,
    hotBorder: hotBorder ?? this.hotBorder,
    glow: glow ?? this.glow,
    mineBorder: mineBorder ?? this.mineBorder,
    bright: bright ?? this.bright,
    label: label ?? this.label,
  );

  @override
  NoteloreTokens lerp(NoteloreTokens? other, double t) {
    if (other == null) return this;
    return NoteloreTokens(
      hot: LinearGradient.lerp(hot, other.hot, t)!,
      hotText: Color.lerp(hotText, other.hotText, t)!,
      hotValue: Color.lerp(hotValue, other.hotValue, t)!,
      hotBorder: Color.lerp(hotBorder, other.hotBorder, t)!,
      glow: RadialGradient.lerp(glow, other.glow, t),
      mineBorder: Color.lerp(mineBorder, other.mineBorder, t)!,
      bright: Color.lerp(bright, other.bright, t)!,
      label: TextStyle.lerp(label, other.label, t)!,
    );
  }
}

/// CSS's `linear-gradient(150deg, …)`: from the top left, mostly downwards.
const _hotFrom = Alignment(-0.6, -1);
const _hotTo = Alignment(0.6, 1);

NoteloreTokens _tokens(ColorScheme colors) {
  final label = TextStyle(
    fontFamily: 'JetBrains Mono',
    fontWeight: FontWeight.w500,
    fontSize: 10.5,
    letterSpacing: 1.6,
    color: colors.primary,
  );
  return colors.brightness == Brightness.light
      ? NoteloreTokens(
          hot: const LinearGradient(
            begin: _hotFrom,
            end: _hotTo,
            colors: [Color(0xFFEA580C), Color(0xFF9A3412)],
          ),
          hotText: const Color(0xFFFFF7ED),
          hotValue: const Color(0xFFFFF7ED),
          hotBorder: colors.outlineVariant,
          glow: null,
          mineBorder: const Color(0xFFEFC4A2),
          bright: const Color(0xFFEA580C),
          label: label,
        )
      : NoteloreTokens(
          hot: const LinearGradient(
            begin: _hotFrom,
            end: _hotTo,
            colors: [Color(0xFF335240), Color(0xFF142019)],
          ),
          hotText: const Color(0xFFD7E3D9),
          hotValue: const Color(0xFFF0B47F),
          hotBorder: colors.primary.withValues(alpha: .3),
          glow: const RadialGradient(
            center: Alignment.topCenter,
            radius: 1.2,
            colors: [Color(0xFF1D3A2A), Color(0x001D3A2A)],
            stops: [0, .65],
          ),
          mineBorder: const Color(0x55D9884F),
          bright: const Color(0xFFEBA26F),
          label: label,
        );
}

/// Lists the bundled fonts' licenses on Flutter's licenses page.
void addFontLicenses() {
  const files = {
    'Fraunces': 'OFL-Fraunces.txt',
    'Plus Jakarta Sans': 'OFL-PlusJakartaSans.txt',
    'JetBrains Mono': 'OFL-JetBrainsMono.txt',
    'Noto Sans': 'OFL.txt',
    'Phosphor Icons': 'MIT-Phosphor.txt',
  };
  LicenseRegistry.addLicense(() async* {
    for (final MapEntry(key: font, value: file) in files.entries) {
      yield LicenseEntryWithLineBreaks([font], await rootBundle.loadString('assets/fonts/$file'));
    }
  });
}

const _serif = TextStyle(fontFamily: 'Fraunces', fontWeight: FontWeight.w600);
const _sans = TextStyle(fontFamily: 'Plus Jakarta Sans');

/// Merged over Material's sizes and colours, so only the faces change.
const _type = TextTheme(
  displayLarge: _serif,
  displayMedium: _serif,
  displaySmall: _serif,
  headlineLarge: _serif,
  headlineMedium: _serif,
  headlineSmall: _serif,
  titleLarge: _serif,
  titleMedium: _serif,
  titleSmall: _serif,
  bodyLarge: _sans,
  bodyMedium: _sans,
  bodySmall: _sans,
  labelLarge: _sans,
  labelMedium: _sans,
  labelSmall: _sans,
);

ThemeData noteloreTheme(Brightness brightness) {
  final colors = brightness == Brightness.light ? kil : orman;
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(_card));
  final edge = BorderSide(color: colors.outlineVariant);
  const tap = Size(48, 48);
  WidgetStateProperty<T> picked<T>(T on, T off) =>
      WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? on : off);
  return ThemeData(
    colorScheme: colors,
    textTheme: _type,
    extensions: [_tokens(colors)],
    textSelectionTheme: TextSelectionThemeData(
      selectionColor: colors.primary.withValues(alpha: 0.35),
      selectionHandleColor: colors.primary,
      cursorColor: colors.primary,
    ),
    scaffoldBackgroundColor: colors.surface,
    visualDensity: VisualDensity.standard,
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) => const Icon(AppIcons.back),
      closeButtonIconBuilder: (_) => const Icon(AppIcons.close),
    ),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_card), side: edge),
    ),
    listTileTheme: ListTileThemeData(shape: rounded, minVerticalPadding: Gap.s),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(_field), borderSide: edge),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_field),
        borderSide: edge,
      ),
      // The focused field stays visible for keyboard users.
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_field),
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
      // An error shows on the field's edge, not only in the line under it.
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_field),
        borderSide: BorderSide(color: colors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_field),
        borderSide: BorderSide(color: colors.error, width: 2),
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
      shape: StadiumBorder(side: edge),
      backgroundColor: colors.surfaceContainerLow,
    ),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: rounded),
    bannerTheme: MaterialBannerThemeData(
      backgroundColor: colors.surfaceContainerLow,
      dividerColor: colors.outlineVariant,
    ),
    // No pill: the chosen tab is told by the accent alone (its labels are sized in Home).
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      iconTheme: picked(
        IconThemeData(color: colors.primary),
        IconThemeData(color: colors.onSurfaceVariant),
      ),
      labelTextStyle: picked(
        _sans.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: colors.primary),
        _sans.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: colors.surface,
      useIndicator: false,
      selectedIconTheme: IconThemeData(color: colors.primary),
      unselectedIconTheme: IconThemeData(color: colors.onSurfaceVariant),
    ),
    // Every picker: a filled, rounded field and a rounded menu above the page.
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(_control), borderSide: edge),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_control),
          borderSide: edge,
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
