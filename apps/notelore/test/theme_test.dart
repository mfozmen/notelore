import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/theme.dart';

void main() {
  test('light and dark share the teal seed, flat cards and 48-point tap targets', () {
    final light = noteloreTheme(Brightness.light);
    final dark = noteloreTheme(Brightness.dark);
    expect(light.colorScheme.brightness, Brightness.light);
    expect(dark.colorScheme.brightness, Brightness.dark);
    for (final theme in [light, dark]) {
      expect(theme.cardTheme.elevation, 0); // outlines, not shadows
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(theme.filledButtonTheme.style!.minimumSize!.resolve({}), const Size(48, 48));
      expect(theme.iconButtonTheme.style!.minimumSize!.resolve({}), const Size(48, 48));
      // The focused field stays visible for keyboard users.
      final focused = theme.inputDecorationTheme.focusedBorder! as OutlineInputBorder;
      expect(focused.borderSide.color, theme.colorScheme.primary);
    }
    expect(Gap.s * 2, Gap.m);
  });

  test('every nature palette has a light and a dark theme from its own colour', () {
    final seeds = <Color>{};
    for (final palette in Palette.values) {
      final light = noteloreTheme(Brightness.light, palette);
      final dark = noteloreTheme(Brightness.dark, palette);
      expect(light.colorScheme.brightness, Brightness.light, reason: palette.name);
      expect(dark.colorScheme.brightness, Brightness.dark, reason: palette.name);
      seeds.add(light.colorScheme.primary);
    }
    expect(seeds, hasLength(Palette.values.length)); // each looks different
    expect(
      noteloreTheme(Brightness.light).colorScheme.primary,
      noteloreTheme(Brightness.light, Palette.lagoon).colorScheme.primary,
    );
    expect(Appearance.system.mode, ThemeMode.system);
    expect(Appearance.light.mode, ThemeMode.light);
    expect(Appearance.dark.mode, ThemeMode.dark);
  });
}
