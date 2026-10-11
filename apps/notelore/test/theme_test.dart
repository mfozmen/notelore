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
}
