import 'dart:math';

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
      expect(theme.cardTheme.elevation, 2); // a gentle shadow, day and night
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

  test('one radius table: card 18, panel 20, field 28, chip 10', () {
    expect((Radii.card, Radii.panel, Radii.field, Radii.chip), (18.0, 20.0, 28.0, 10.0));
  });

  test('the shapes: crisp cards with a soft shadow, a round bordered field, plain navigation', () {
    for (final theme in [noteloreTheme(Brightness.light), noteloreTheme(Brightness.dark)]) {
      final c = theme.colorScheme;
      // A hairline and nothing drawn inside it: no top light, no glow.
      final card = theme.cardTheme.shape!;
      expect(card.runtimeType, RoundedRectangleBorder);
      expect(card, softBorder(c, BorderRadius.circular(Radii.card)));
      expect((card as RoundedRectangleBorder).side.width, 1);
      // Raised in both themes.
      expect(theme.cardTheme.elevation, greaterThan(0));
      expect(theme.cardTheme.shadowColor!.a, greaterThan(0));
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

  testWidgets('hover and press tint with the accent; a keyboard focus is a 2-point ring', (
    tester,
  ) async {
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    for (final theme in [noteloreTheme(Brightness.light), noteloreTheme(Brightness.dark)]) {
      final c = theme.colorScheme;
      // A bare InkWell takes these: never Material's grey.
      expect(theme.hoverColor, c.primary.withValues(alpha: .08));
      expect(theme.highlightColor, c.primary.withValues(alpha: .12));
      expect(theme.focusColor, c.primary.withValues(alpha: .12));
      final buttons = {
        theme.textButtonTheme.style!: c.primary,
        theme.iconButtonTheme.style!: c.primary,
        theme.outlinedButtonTheme.style!: c.primary,
        // On the orb the accent would not show; its own ink does.
        theme.filledButtonTheme.style!: c.onPrimary,
      };
      for (final MapEntry(key: style, value: ink) in buttons.entries) {
        expect(style.overlayColor!.resolve({WidgetState.hovered}), ink.withValues(alpha: .08));
        expect(style.overlayColor!.resolve({WidgetState.focused}), ink.withValues(alpha: .08));
        expect(
          style.overlayColor!.resolve({WidgetState.hovered, WidgetState.pressed}),
          ink.withValues(alpha: .12),
        );
        expect(style.overlayColor!.resolve({}), isNull);
        FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
        expect(style.side!.resolve({WidgetState.focused}), BorderSide(color: c.primary, width: 2));
        // A finger focuses nothing it should ring.
        FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
        expect(
          style.side!.resolve({WidgetState.focused}),
          isNot(BorderSide(color: c.primary, width: 2)),
        );
      }
      expect(
        theme.outlinedButtonTheme.style!.side!.resolve({}),
        BorderSide(color: c.outlineVariant),
      );
      expect(theme.textButtonTheme.style!.side!.resolve({}), isNull);
      // Menus: the soft card, not Material's square sheet.
      final menu = theme.popupMenuTheme;
      expect(menu.shape, softBorder(c, BorderRadius.circular(Radii.panel)));
      expect(menu.color, c.surfaceContainerHigh);
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

  test('the tokens a scheme has no role for: decision card, night glow, mono label', () {
    final kil = noteloreTheme(Brightness.light).extension<NoteloreTokens>()!;
    expect(kil.hot.colors, const [Color(0xFFC2410C), Color(0xFF9A3412)]);
    expect(kil.hotValue, Colors.white);
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
    expect(orman.glow!.colors.first, const Color(0xFF1D3A2A));
    expect(orman.glow!.center, Alignment.topCenter);
    expect(orman.mineBorder, const Color(0x55D9884F));
    expect(orman.bright, const Color(0xFFEBA26F));
    expect(orman.label.color, const Color(0xFFD9884F));
  });

  test(
    "a found decision's words read at 4.5:1 or more anywhere on its card, brightest the value",
    () {
      for (final brightness in Brightness.values) {
        final t = noteloreTheme(brightness).extension<NoteloreTokens>()!;
        final words = [t.hotLabel, t.hotValue, t.hotReason, t.hotSource, t.hotLink];
        for (final fill in t.hot.colors) {
          for (final word in words) {
            expect(contrast(word, fill), greaterThanOrEqualTo(4.5), reason: '$brightness $word');
          }
        }
        // A hierarchy, not all one colour: the value brightest, the source softest.
        final light = [for (final w in words) w.computeLuminance()];
        expect(words.toSet(), hasLength(words.length));
        expect(light.reduce(max), light[1]);
        expect(light[3], lessThan(light[2]));
        expect(light[2], lessThan(light[1]));
      }
    },
  );

  test('the tokens copy and blend between day and night', () {
    final kil = noteloreTheme(Brightness.light).extension<NoteloreTokens>()!;
    final orman = noteloreTheme(Brightness.dark).extension<NoteloreTokens>()!;
    expect(kil.copyWith().hot, kil.hot);
    final changed = kil.copyWith(
      hot: orman.hot,
      hotLabel: orman.hotLabel,
      hotValue: orman.hotValue,
      hotReason: orman.hotReason,
      hotSource: orman.hotSource,
      hotLink: orman.hotLink,
      hotBorder: orman.hotBorder,
      glow: orman.glow,
      mineBorder: orman.mineBorder,
      bright: orman.bright,
      label: orman.label,
    );
    expect(
      [
        changed.hot,
        changed.hotLabel,
        changed.hotValue,
        changed.hotReason,
        changed.hotSource,
        changed.hotLink,
        changed.hotBorder,
        changed.glow,
        changed.mineBorder,
        changed.bright,
        changed.label,
      ],
      [
        orman.hot,
        orman.hotLabel,
        orman.hotValue,
        orman.hotReason,
        orman.hotSource,
        orman.hotLink,
        orman.hotBorder,
        orman.glow,
        orman.mineBorder,
        orman.bright,
        orman.label,
      ],
    );
    expect(kil.lerp(orman, 0).hotLabel, kil.hotLabel);
    final end = kil.lerp(orman, 1);
    expect(
      [
        end.hotLabel,
        end.hotValue,
        end.hotReason,
        end.hotSource,
        end.hotLink,
        end.hotBorder,
        end.mineBorder,
        end.bright,
      ],
      [
        orman.hotLabel,
        orman.hotValue,
        orman.hotReason,
        orman.hotSource,
        orman.hotLink,
        orman.hotBorder,
        orman.mineBorder,
        orman.bright,
      ],
    );
    expect(end.hot.colors, orman.hot.colors);
    expect(kil.lerp(null, .5), same(kil));
  });
}
