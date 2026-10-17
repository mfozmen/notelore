import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore_core/notelore_core.dart';

import 'app_test.dart' show connect, phone, pumpApp;
import 'support.dart';

/// A desktop window of [width] x 1000 logical pixels.
void desktop(WidgetTester tester, double width) {
  WidgetController.hitTestWarningShouldBeFatal = true;
  addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);
  tester.view
    ..physicalSize = Size(width, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('Google sign-in on a wide window: a card of a readable width, centred (#296)', (
    tester,
  ) async {
    desktop(tester, 1280);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpApp(tester, Harness(auth: FakeAuth()));
    final card = find.byKey(const Key('google-card'));
    expect(tester.getSize(card).width, lessThanOrEqualTo(480));
    expect(tester.getCenter(card).dx, closeTo(640, 1));
    // Dark: Google's dark G.
    expect(
      find.byWidgetPredicate((w) => w is Image && '${w.image}'.contains('g_dark.png')),
      findsOneWidget,
    );
  });

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

  testWidgets('a draft survives the side rail and a resize to the phone layout', (tester) async {
    desktop(tester, 1600);
    await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    String draft() => tester.widget<TextField>(find.byKey(const Key('message'))).controller!.text;
    await tester.enterText(find.byKey(const Key('message')), 'half a thought');
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    expect(draft(), 'half a thought');
    phone(tester); // the layout changes under the chat
    await tester.pumpAndSettle();
    expect(draft(), 'half a thought');
  });

  testWidgets('wide settings have their own section for the app lock', (tester) async {
    desktop(tester, 1600);
    await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('settings-sections')),
        matching: find.text('App lock'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Turn on'), findsOneWidget);
    expect(find.textContaining('opens without asking'), findsOneWidget);
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
    expect(find.text('Kitaplar'), findsNWidgets(2)); // in the list and the note's heading
    expect(tester.widget<ListTile>(find.widgetWithText(ListTile, 'Kitaplar')).selected, isTrue);
    expect(find.text('Pick a note to read it here.'), findsNothing);

    // Deleting the open note empties the reader.
    await tester.tap(find.byTooltip('Delete').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Kitaplar'), findsNothing);
    expect(find.text('Pick a note to read it here.'), findsOneWidget);
  });

  testWidgets('the open note follows changes from a sync or the assistant', (tester) async {
    desktop(tester, 1600);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    final path = createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitaplar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Dune'), findsNothing);

    // Added to elsewhere the same day (the date stays): the reader shows it.
    final text = File(path).readAsStringSync();
    File(path).writeAsStringSync('$text- Dune${String.fromCharCode(10)}');
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Dune'), findsOneWidget);

    // Archived elsewhere: the reader empties.
    await session.deleteNote(session.listNotes().single);
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Pick a note to read it here.'), findsOneWidget);
  });

  testWidgets('the side rail and the side-by-side panes start at the same window width', (
    tester,
  ) async {
    desktop(tester, 900); // the rail takes some of it: the body is narrower than 840
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    expect(find.byType(NavigationRail), findsOneWidget);
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('Pick a note to read it here.'), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-sections')), findsOneWidget);
  });
}
