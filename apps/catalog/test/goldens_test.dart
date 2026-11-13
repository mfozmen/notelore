import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/session.dart';
import 'package:notelore/src/theme.dart';
import 'package:notelore_catalog/catalog.dart';
import 'package:notelore_catalog/fake.dart';
import 'package:notelore_catalog/fonts.dart';

/// Golden renders of every main screen, compared on Linux only: other systems
/// rasterise the same fonts a little differently. Update them on purpose, with
/// the reason in the PR: `flutter test --update-goldens test/goldens_test.dart`
/// on Linux, or the Flutter workflow run by hand with `update_goldens`.
void main() {
  late Directory dir;
  late Session session;

  setUpAll(() async {
    await loadAppFonts();
    // The app draws Phosphor, but Material's own widgets (an expansion arrow) use its icons.
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    dir = Directory.systemTemp.createTempSync('notelore_goldens_');
    session = await fakeSession(root: dir);
  });

  tearDownAll(() {
    session.dispose();
    dir.deleteSync(recursive: true);
  });

  for (final MapEntry(key: screen, value: build) in catalogScreens.entries) {
    final name = screen.toLowerCase().replaceAll(' ', '_');
    for (final viewport in catalogViewports) {
      final device = '${viewport.width.toInt()}x${viewport.height.toInt()}';
      for (final brightness in Brightness.values) {
        for (final scale in [1.0, 2.0]) {
          final golden = '${name}_${device}_${brightness.name}_${scale.toInt()}x';
          testWidgets(golden, skip: !Platform.isLinux, (tester) async {
            // One logical pixel a pixel: the phone's layout, in small files.
            tester.view
              ..physicalSize = viewport.size
              ..devicePixelRatio = 1;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.view.reset);
            addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
            addTearDown(() => tester.pumpWidget(const SizedBox()));
            await tester.pumpWidget(
              MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: noteloreTheme(brightness),
                home: Builder(builder: (context) => build(context, session)),
              ),
            );
            await tester.pumpAndSettle();
            await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$golden.png'));
          });
        }
      }
    }
  }
}
