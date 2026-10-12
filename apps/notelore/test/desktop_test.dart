import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore_core/notelore_core.dart';

import 'app_test.dart' show connect, phone, pumpApp;
import 'support.dart';

/// A desktop window of [width] x 1000 logical pixels.
void desktop(WidgetTester tester, double width) {
  WidgetController.hitTestWarningShouldBeFatal = true;
  tester.view
    ..physicalSize = Size(width, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('a wide window navigates from a side rail; a phone from the bottom bar', (
    tester,
  ) async {
    desktop(tester, 1600);
    await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    expect(find.byType(NavigationBar), findsNothing);
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isTrue); // room for the labels
    expect(find.text('Notelore'), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Provider'), findsOneWidget);

    desktop(tester, 1000); // narrower: icons only
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).extended, isFalse);

    phone(tester);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('chat on a wide window is a readable column, not the full width', (tester) async {
    desktop(tester, 1920);
    await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    expect(tester.getSize(find.byType(TextField).last).width, lessThanOrEqualTo(840));
  });

  testWidgets('notes on a wide window: the list and the open note side by side', (tester) async {
    desktop(tester, 1600);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    createNote(harness.paths.notes.path, 'project', 'Mopsos', today: today);
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('Pick a note to read it here.'), findsOneWidget);

    await tester.tap(find.text('Kitaplar'));
    await tester.pumpAndSettle();
    expect(find.text('Mopsos'), findsOneWidget); // the list stays
    expect(find.text('Kitaplar'), findsNWidgets(2)); // in the list and over the note
    expect(find.text('Pick a note to read it here.'), findsNothing);

    // Deleting the open note empties the reader.
    await tester.tap(find.byTooltip('Delete').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Kitaplar'), findsNothing);
    expect(find.text('Pick a note to read it here.'), findsOneWidget);
  });
}
