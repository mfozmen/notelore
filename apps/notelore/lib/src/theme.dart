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
const _card = 22.0;
const _field = 28.0;
const _soft = 20.0;

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
  /// The answer's words: a step under the body size, with room between lines.
  static const double size = 13;
  static const double lineHeight = 1.6;

  /// A list card's row, and the accent number that starts it.
  static const listRow = EdgeInsets.symmetric(horizontal: 14, vertical: 10);
  static const double numberSize = 11.5;

  /// The closing line after a list, a little quieter than the rest.
  static const double closing = .78;

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

/// The orb's fill for a control with words or a glyph on it: lit at its top
/// left, deeper at its rim, and [ColorScheme.onPrimary] keeps 4.5:1 on it
/// everywhere but the far corner.
RadialGradient orbFill(ColorScheme colors) {
  final accent = colors.primary;
  final light = colors.brightness == Brightness.light;
  return RadialGradient(
    center: const Alignment(-0.7, -0.9),
    radius: 1.6,
    stops: const [0, .45, 1],
    colors: [
      Color.lerp(accent, Colors.white, light ? .14 : .3)!,
      accent,
      light ? const Color(0xFF9A3412) : Color.lerp(accent, Colors.black, .15)!,
    ],
  );
}

/// [child] dimmed and a little smaller while [pressed]: the press feedback
/// that stands in for a ripple.
Widget pressFeedback({required bool pressed, required Widget child}) => AnimatedScale(
  scale: pressed ? .96 : 1,
  duration: const Duration(milliseconds: 90),
  child: AnimatedOpacity(
    opacity: pressed ? .75 : 1,
    duration: const Duration(milliseconds: 90),
    child: child,
  ),
);

/// The accent's soft glow under an orb.
List<BoxShadow> orbGlow(ColorScheme colors, {double blur = 18, double y = 6}) => [
  BoxShadow(color: colors.primary.withValues(alpha: .45), offset: Offset(0, y), blurRadius: blur),
];

/// A soft card's edge on [colors]: by day a light along its top, at night a
/// faint glow of the accent inside.
SoftBorder softBorder(ColorScheme colors, BorderRadiusGeometry radius) {
  final light = colors.brightness == Brightness.light;
  return SoftBorder(
    borderRadius: radius,
    side: BorderSide(
      color: light ? colors.outlineVariant.withValues(alpha: .75) : colors.outlineVariant,
    ),
    highlight: Colors.white.withValues(alpha: light ? .8 : .07),
    glow: light ? Colors.transparent : colors.primary.withValues(alpha: .16),
  );
}

/// A rounded rectangle with a hairline, a 1-point light along its top edge and
/// a blurred [glow] inside it, all drawn over the content's edge.
@immutable
class SoftBorder extends RoundedRectangleBorder {
  const SoftBorder({required this.highlight, required this.glow, super.side, super.borderRadius});

  final Color highlight;
  final Color glow;

  // A button resolves its shape through copyWith; the inherited one returns a plain border.
  @override
  SoftBorder copyWith({BorderSide? side, BorderRadiusGeometry? borderRadius}) => SoftBorder(
    highlight: highlight,
    glow: glow,
    side: side ?? this.side,
    borderRadius: borderRadius ?? this.borderRadius,
  );

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final edge = borderRadius.resolve(textDirection).toRRect(rect);
    canvas
      ..save()
      ..clipRRect(edge)
      ..drawDRRect(
        edge.inflate(40),
        edge,
        Paint()
          ..color = glow
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      )
      // Where the edge and the edge one point lower differ, inside: the top rim.
      ..drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRRect(edge)
          ..addRRect(edge.shift(const Offset(0, 1))),
        Paint()..color = highlight,
      )
      ..restore();
    super.paint(canvas, rect, textDirection: textDirection);
  }

  @override
  bool operator ==(Object other) =>
      other is SoftBorder && super == other && other.highlight == highlight && other.glow == glow;

  @override
  int get hashCode => Object.hash(super.hashCode, highlight, glow);
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
  final light = brightness == Brightness.light;
  // No ripple: a press dims and shrinks the button's insides a little instead.
  Widget press(BuildContext _, Set<WidgetState> states, Widget? child) =>
      pressFeedback(pressed: states.contains(WidgetState.pressed), child: child!);
  final noPressTint = WidgetStateProperty.resolveWith<Color?>(
    (states) => states.contains(WidgetState.pressed) ? Colors.transparent : null,
  );
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
    splashFactory: NoSplash.splashFactory,
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
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerLow,
      // Soft, not raised: a faint accent shadow by day, none at night.
      elevation: light ? 2 : 0,
      shadowColor: colors.primary.withValues(alpha: .35),
      shape: softBorder(colors, BorderRadius.circular(_card)),
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
    // The main action is an orb: lit, with the accent's glow under it.
    filledButtonTheme: FilledButtonThemeData(
      style:
          FilledButton.styleFrom(
            minimumSize: tap,
            shape: const StadiumBorder(),
            foregroundColor: colors.onPrimary,
          ).copyWith(
            overlayColor: noPressTint,
            backgroundBuilder: (context, states, child) => states.contains(WidgetState.disabled)
                ? child!
                : press(
                    context,
                    states,
                    DecoratedBox(
                      decoration: ShapeDecoration(
                        shape: const StadiumBorder(),
                        gradient: orbFill(colors),
                        shadows: orbGlow(colors, blur: 16),
                      ),
                      child: child,
                    ),
                  ),
          ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: tap,
        shape: const StadiumBorder(),
        backgroundColor: colors.surfaceContainerLow,
        side: edge,
      ).copyWith(overlayColor: noPressTint, backgroundBuilder: press),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: tap)
          .copyWith(overlayColor: noPressTint, backgroundBuilder: press),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: tap)
          .copyWith(overlayColor: noPressTint, backgroundBuilder: press),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colors.primary,
      foregroundColor: colors.onPrimary,
      shape: const StadiumBorder(),
      elevation: 3,
      focusElevation: 3,
      hoverElevation: 4,
      highlightElevation: 1,
    ),
    // A chosen chip glows; the others sit soft on the page.
    chipTheme: ChipThemeData(
      shape: StadiumBorder(side: BorderSide(color: colors.outlineVariant)),
      backgroundColor: colors.surfaceContainerLow,
      elevation: 2,
      pressElevation: 0,
      shadowColor: Colors.transparent,
      selectedShadowColor: colors.primary.withValues(alpha: .6),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      side: BorderSide(color: colors.outline, width: 1.5),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: softBorder(colors, BorderRadius.circular(24)),
      backgroundColor: colors.surfaceContainerLow,
      contentTextStyle: _sans.copyWith(fontSize: 14, color: colors.onSurface),
      actionTextColor: colors.onPrimaryContainer,
      actionBackgroundColor: colors.primaryContainer,
      closeIconColor: colors.onSurfaceVariant,
      elevation: light ? 4 : 2,
    ),
    bannerTheme: MaterialBannerThemeData(
      backgroundColor: colors.surfaceContainerLow,
      dividerColor: colors.outlineVariant,
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
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(_soft), borderSide: edge),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_soft),
          borderSide: edge,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_soft),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
      ),
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerHigh),
        elevation: const WidgetStatePropertyAll(3),
        shadowColor: WidgetStatePropertyAll(colors.primary.withValues(alpha: .35)),
        shape: WidgetStatePropertyAll(softBorder(colors, BorderRadius.circular(_soft))),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: Gap.xs)),
      ),
    ),
    dividerTheme: DividerThemeData(color: colors.outlineVariant, space: 1),
  );
}
