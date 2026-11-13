import 'package:flutter/services.dart';

/// The app's faces by family, as `apps/notelore/pubspec.yaml` bundles them.
const appFonts = {
  'Fraunces': ['Fraunces-SemiBold.ttf', 'Fraunces-SemiBoldItalic.ttf'],
  'Plus Jakarta Sans': [
    'PlusJakartaSans-Regular.ttf',
    'PlusJakartaSans-Italic.ttf',
    'PlusJakartaSans-Medium.ttf',
    'PlusJakartaSans-SemiBold.ttf',
    'PlusJakartaSans-Bold.ttf',
  ],
  'JetBrains Mono': ['JetBrainsMono-Medium.ttf'],
  'Phosphor': ['Phosphor-Regular.ttf'],
  'Phosphor Fill': ['Phosphor-Fill.ttf'],
  'Phosphor Duotone': ['Phosphor-Duotone.ttf'],
};

/// Registers the app's fonts under their plain family names. A dependency's
/// fonts are bundled as `packages/notelore/<family>`, which the app's theme
/// and icons, naming the plain family, would never find.
Future<void> loadAppFonts() async {
  for (final MapEntry(:key, :value) in appFonts.entries) {
    final loader = FontLoader(key);
    for (final file in value) {
      loader.addFont(rootBundle.load('packages/notelore/assets/fonts/$file'));
    }
    await loader.load();
  }
}
