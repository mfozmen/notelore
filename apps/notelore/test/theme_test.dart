import 'package:flutter/foundation.dart' show LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/theme.dart';

/// WCAG contrast ratio of [a] on [b].
double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
}

void main() {
  testWidgets("the bundled fonts' licenses are on Flutter's licenses page", (tester) async {
    addFontLicenses();
    final entries = await tester.runAsync(() => LicenseRegistry.licenses.toList());
    Set<String> under(String license) => {
      for (final entry in entries!)
        if (entry.paragraphs.any((p) => p.text.contains(license))) ...entry.packages,
    };
    expect(
      under('SIL OPEN FONT LICENSE'),
      containsAll(['Fraunces', 'Plus Jakarta Sans', 'JetBrains Mono', 'Noto Sans']),
    );
    expect(under('MIT License'), contains('Phosphor Icons'));
  });

  test('light and dark: soft cards and 48-point tap targets', () {
    final light = noteloreTheme(Brightness.light);
    final dark = noteloreTheme(Brightness.dark);
    expect(light.colorScheme.brightness, Brightness.light);
    expect(dark.colorScheme.brightness, Brightness.dark);
    for (final theme in [light, dark]) {
      // A gentle shadow by day; at night the card's inner glow does it.
      expect(theme.cardTheme.elevation, theme.brightness == Brightness.light ? 2 : 0);
      expect(theme.splashFactory, NoSplash.splashFactory);
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(theme.filledButtonTheme.style!.minimumSize!.resolve({}), const Size(48, 48));
      expect(theme.iconButtonTheme.style!.minimumSize!.resolve({}), const Size(48, 48));
      // The focused field stays visible for keyboard users.
      final focused = theme.inputDecorationTheme.focusedBorder! as OutlineInputBorder;
      expect(focused.borderSide.color, theme.colorScheme.primary);
      // A field in error says so with its border, not only the line under it.
      for (final error in [
        theme.inputDecorationTheme.errorBorder!,
        theme.inputDecorationTheme.focusedErrorBorder!,
      ]) {
        expect((error as OutlineInputBorder).borderSide.color, theme.colorScheme.error);
      }
    }
    expect(Gap.s * 2, Gap.m);
    // A bubble's small corner is on its speaker's side; its width leaves a gutter.
    expect(bubbleRadius(mine: true).bottomRight, const Radius.circular(4));
    expect(bubbleRadius(mine: false).bottomLeft, const Radius.circular(4));
    expect(Layout.bubble(400), 340);
    expect(Layout.bubble(1000), 560);
    expect(Appearance.system.mode, ThemeMode.system);
    expect(Appearance.light.mode, ThemeMode.light);
    expect(Appearance.dark.mode, ThemeMode.dark);
  });

  test('Kil by day and Orman by night take the mockup colours (#782)', () {
    final kil = noteloreTheme(Brightness.light).colorScheme;
    expect(
      [
        kil.surface,
        kil.surfaceContainerLow,
        kil.outlineVariant,
        kil.onSurface,
        kil.primary,
        kil.onPrimary,
        kil.primaryContainer,
        kil.onPrimaryContainer,
      ],
      const [
        Color(0xFFF6EFE6),
        Color(0xFFFFFAF4),
        Color(0xFFEADCCB),
        Color(0xFF2B1A12),
        Color(0xFFC2410C),
        Color(0xFFFFFFFF),
        Color(0xFFFBE6D4),
        Color(0xFF4A2312),
      ],
    );
    final orman = noteloreTheme(Brightness.dark).colorScheme;
    expect(
      [
        orman.surface,
        orman.surfaceContainerLow,
        orman.outlineVariant,
        orman.onSurface,
        orman.onSurfaceVariant,
        orman.primary,
        orman.primaryContainer,
        orman.onPrimaryContainer,
      ],
      const [
        Color(0xFF0C120E),
        Color(0xFF131B16),
        Color(0xFF223026),
        Color(0xFFE9EFE9),
        Color(0xFF8FA093),
        Color(0xFFD9884F),
        Color(0xFF18231C),
        Color(0xFFF6E3D2),
      ],
    );
  });

  test('text on every surface it sits on reads at 4.5:1 or more', () {
    for (final brightness in Brightness.values) {
      final c = noteloreTheme(brightness).colorScheme;
      final pairs = {
        'onSurface': (c.onSurface, c.surface),
        'muted': (c.onSurfaceVariant, c.surface),
        'muted on a card': (c.onSurfaceVariant, c.surfaceContainerLow),
        'muted on the highest': (c.onSurfaceVariant, c.surfaceContainerHighest),
        'primary': (c.primary, c.surface),
        'primary on a card': (c.primary, c.surfaceContainerLow),
        'onPrimary': (c.onPrimary, c.primary),
        'mine': (c.onPrimaryContainer, c.primaryContainer),
        'secondary': (c.onSecondaryContainer, c.secondaryContainer),
        'onSecondary': (c.onSecondary, c.secondary),
        'tertiary': (c.onTertiaryContainer, c.tertiaryContainer),
        'onTertiary': (c.onTertiary, c.tertiary),
        'error': (c.error, c.surface),
        'onError': (c.onError, c.error),
        'errorContainer': (c.onErrorContainer, c.errorContainer),
        'inverse': (c.onInverseSurface, c.inverseSurface),
      };
      for (final MapEntry(:key, value: (fg, bg)) in pairs.entries) {
        expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: '$brightness $key');
      }
    }
  });

  test('no teal is left anywhere in either scheme', () {
    for (final brightness in Brightness.values) {
      final c = noteloreTheme(brightness).colorScheme;
      for (final color in [c.primary, c.secondary, c.tertiary, c.surfaceTint, c.inversePrimary]) {
        final hue = HSVColor.fromColor(color).hue;
        expect(hue < 150 || hue > 200, isTrue, reason: '$brightness $color');
      }
    }
  });

  test('the type: Fraunces for titles, Plus Jakarta Sans for the rest, bundled', () {
    final text = noteloreTheme(Brightness.light).textTheme;
    for (final title in [
      text.displayLarge,
      text.displayMedium,
      text.displaySmall,
      text.headlineLarge,
      text.headlineMedium,
      text.headlineSmall,
      text.titleLarge,
      text.titleMedium,
      text.titleSmall,
    ]) {
      expect((title!.fontFamily, title.fontWeight), ('Fraunces', FontWeight.w600));
    }
    for (final body in [
      text.bodyLarge,
      text.bodyMedium,
      text.bodySmall,
      text.labelLarge,
      text.labelMedium,
      text.labelSmall,
    ]) {
      expect(body!.fontFamily, 'Plus Jakarta Sans');
    }
  });

  test('the shapes: soft round cards, a round bordered field, plain navigation', () {
    for (final theme in [noteloreTheme(Brightness.light), noteloreTheme(Brightness.dark)]) {
      final c = theme.colorScheme;
      final card = theme.cardTheme.shape! as SoftBorder;
      expect(card.borderRadius, BorderRadius.circular(22));
      expect(card, softBorder(c, BorderRadius.circular(22)));
      // By day a light along the top; at night the accent glows inside.
      expect(card.glow.a, theme.brightness == Brightness.light ? 0 : greaterThan(0));
      expect(theme.cardTheme.color, c.surfaceContainerLow);
      final field = theme.inputDecorationTheme;
      expect(field.fillColor, c.surfaceContainerLow);
      final enabled = field.enabledBorder! as OutlineInputBorder;
      expect(enabled.borderRadius, BorderRadius.circular(28));
      expect(enabled.borderSide.color, c.outlineVariant);
      expect((theme.chipTheme.shape! as StadiumBorder).side.color, c.outlineVariant);
      expect(theme.appBarTheme.backgroundColor, c.surface);
      final rail = theme.navigationRailTheme;
      expect(rail.backgroundColor, c.surface);
      expect(rail.useIndicator, isFalse);
      expect(rail.selectedIconTheme!.color, c.primary);
      expect(rail.unselectedIconTheme!.color, c.onSurfaceVariant);
    }
  });

  test('words on an orb read at 4.5:1 or more, but at its lit corner', () {
    for (final brightness in Brightness.values) {
      final c = noteloreTheme(brightness).colorScheme;
      final orb = orbFill(c).colors;
      expect(orb[1], c.primary);
      for (final color in orb.skip(1)) {
        expect(contrast(c.onPrimary, color), greaterThanOrEqualTo(4.5), reason: '$brightness');
      }
      expect(contrast(c.onPrimary, orb.first), greaterThanOrEqualTo(4), reason: '$brightness');
      expect(orbGlow(c).single.color, c.primary.withValues(alpha: .45));
    }
  });

  test('a soft border equals another only with the same light and glow', () {
    final c = noteloreTheme(Brightness.dark).colorScheme;
    final one = softBorder(c, BorderRadius.circular(8));
    expect(one, softBorder(c, BorderRadius.circular(8)));
    expect(one.hashCode, softBorder(c, BorderRadius.circular(8)).hashCode);
    expect(
      one == softBorder(noteloreTheme(Brightness.light).colorScheme, one.borderRadius),
      isFalse,
    );
    expect(one == RoundedRectangleBorder(borderRadius: one.borderRadius, side: one.side), isFalse);
  });

  test('a soft border keeps its light and glow when a button copies it with its side', () {
    final c = noteloreTheme(Brightness.dark).colorScheme;
    final one = softBorder(c, BorderRadius.circular(8));
    expect(one.copyWith(), one);
    final round = one.copyWith(
      side: const BorderSide(width: 2),
      borderRadius: BorderRadius.circular(19),
    );
    expect(round.glow, one.glow);
    expect(round.highlight, one.highlight);
    expect(round.side.width, 2);
    expect(round.borderRadius, BorderRadius.circular(19));
  });

  test('the tokens a scheme has no role for: decision card, night glow, mono label', () {
    final kil = noteloreTheme(Brightness.light).extension<NoteloreTokens>()!;
    expect(kil.hot.colors, const [Color(0xFFEA580C), Color(0xFF9A3412)]);
    expect((kil.hotText, kil.hotValue), (const Color(0xFFFFF7ED), const Color(0xFFFFF7ED)));
    expect(kil.hotBorder, const Color(0xFFEADCCB));
    expect(kil.glow, isNull); // only the night has one
    expect(kil.mineBorder, const Color(0xFFEFC4A2));
    expect(kil.bright, const Color(0xFFEA580C));
    expect(
      (kil.label.fontFamily, kil.label.fontWeight, kil.label.fontSize, kil.label.letterSpacing),
      ('JetBrains Mono', FontWeight.w500, 10.5, 1.6),
    );
    expect(kil.label.color, const Color(0xFFC2410C));

    final orman = noteloreTheme(Brightness.dark).extension<NoteloreTokens>()!;
    expect(orman.hot.colors, const [Color(0xFF335240), Color(0xFF142019)]);
    expect((orman.hotText, orman.hotValue), (const Color(0xFFD7E3D9), const Color(0xFFF0B47F)));
    expect(orman.hotBorder, const Color(0xFFD9884F).withValues(alpha: .3));
    expect(orman.glow!.colors.first, const Color(0xFF1D3A2A));
    expect(orman.glow!.center, Alignment.topCenter);
    expect(orman.mineBorder, const Color(0x55D9884F));
    expect(orman.bright, const Color(0xFFEBA26F));
    expect(orman.label.color, const Color(0xFFD9884F));
  });

  test('the tokens copy and blend between day and night', () {
    final kil = noteloreTheme(Brightness.light).extension<NoteloreTokens>()!;
    final orman = noteloreTheme(Brightness.dark).extension<NoteloreTokens>()!;
    expect(kil.copyWith().hot, kil.hot);
    final changed = kil.copyWith(
      hot: orman.hot,
      hotText: orman.hotText,
      hotValue: orman.hotValue,
      hotBorder: orman.hotBorder,
      glow: orman.glow,
      mineBorder: orman.mineBorder,
      bright: orman.bright,
      label: orman.label,
    );
    expect(
      [
        changed.hot,
        changed.hotText,
        changed.hotValue,
        changed.hotBorder,
        changed.glow,
        changed.mineBorder,
        changed.bright,
        changed.label,
      ],
      [
        orman.hot,
        orman.hotText,
        orman.hotValue,
        orman.hotBorder,
        orman.glow,
        orman.mineBorder,
        orman.bright,
        orman.label,
      ],
    );
    expect(kil.lerp(orman, 0).hotText, kil.hotText);
    final end = kil.lerp(orman, 1);
    expect(
      [end.hotText, end.hotValue, end.mineBorder, end.bright],
      [orman.hotText, orman.hotValue, orman.mineBorder, orman.bright],
    );
    expect(end.hot.colors, orman.hot.colors);
    expect(kil.lerp(null, .5), same(kil));
  });
}
