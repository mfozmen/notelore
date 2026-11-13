import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/session.dart';
import 'package:notelore/src/theme.dart';
import 'package:notelore_catalog/catalog.dart';
import 'package:notelore_catalog/fake.dart';
import 'package:notelore_catalog/fonts.dart';
import 'package:widgetbook/widgetbook.dart';

/// The fake session on a temp folder the test removes; the app is unmounted first.
Future<Session> openFake(WidgetTester tester) async {
  final dir = Directory.systemTemp.createTempSync('notelore_catalog_test_');
  final session = (await tester.runAsync(() => fakeSession(root: dir)))!;
  addTearDown(() => dir.deleteSync(recursive: true));
  addTearDown(session.dispose);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  return session;
}

void main() {
  testWidgets('the app faces load from the notelore package', (tester) async {
    await tester.runAsync(loadAppFonts); // throws when a file is not bundled
  });

  testWidgets('the catalog opens on its rules, components and screens', (tester) async {
    tester.view
      ..physicalSize = const Size(1600, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = await openFake(tester);
    await tester.pumpWidget(
      Widgetbook.material(directories: catalogDirectories(session), addons: catalogAddons),
    );
    await tester.pumpAndSettle();
    for (final name in ['Rules', 'Components', 'Screens']) {
      expect(find.text(name), findsWidgets, reason: name);
    }
  });

  for (final viewport in catalogViewports) {
    testWidgets('every screen builds on fake notes: ${viewport.name}', (tester) async {
      tester.view
        ..physicalSize = viewport.size * viewport.pixelRatio
        ..devicePixelRatio = viewport.pixelRatio;
      addTearDown(tester.view.reset);
      final session = await openFake(tester);
      for (final MapEntry(:key, :value) in catalogScreens.entries) {
        await tester.pumpWidget(
          MaterialApp(
            theme: noteloreTheme(Brightness.light),
            home: Builder(builder: (context) => value(context, session)),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: key);
      }
    });
  }
}
