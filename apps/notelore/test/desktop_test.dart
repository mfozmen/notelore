import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/icons.dart';
import 'package:notelore/src/note_view.dart';
import 'package:notelore/src/theme.dart';
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
  testWidgets('setup: a readable card on the desktop (#337)', (tester) async {
    desktop(tester, 1280);
    await pumpApp(tester, Harness());
    expect(tester.getSize(find.byKey(const Key('setup-card'))).width, lessThanOrEqualTo(480));
    expect(
      find.descendant(
        of: find.byKey(const Key('setup-card')),
        matching: find.widgetWithText(FilledButton, 'Next'),
      ),
      findsOneWidget,
    );
  });

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
    final colors = Theme.of(tester.element(find.byType(NavigationRail))).colorScheme;
    expect(rail.selectedLabelTextStyle!.color, colors.primary); // the chosen tab in the accent
    expect(find.text('Notelore'), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('CONNECTED MODELS'), findsOneWidget);

    desktop(tester, 1000); // narrower: icons only
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).extended, isFalse);

    phone(tester);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    // A hairline over the bar, as the rail has its divider beside it.
    final line = tester.widget<DecoratedBox>(
      find.ancestor(of: find.byType(NavigationBar), matching: find.byType(DecoratedBox)).first,
    );
    expect(
      (line.decoration as BoxDecoration).border,
      Border(top: BorderSide(color: colors.outlineVariant)),
    );
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

  testWidgets('chat on a wide window uses the width for its composer (#697, #771)', (tester) async {
    desktop(tester, 1920);
    await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    final width = tester.getSize(find.byType(TextField).last).width;
    expect(width, greaterThan(1000));
    expect(width, lessThanOrEqualTo(Layout.chat));
  });

  testWidgets('chat on a wide window uses the width: bubbles, composer, zoom (#697)', (
    tester,
  ) async {
    desktop(tester, 1600);
    final session = await pumpApp(tester, Harness(answers: ['Saved.', 'Saved again.']));
    await connect(tester, key: 'k');
    const message =
        'Kitaplari rafa koy ve haftaya dentist randevusunu hatirlat, sonra da kutuphane icin yeni bir proje notu ac ve icini doldur, boylece satirlar dolacak kadar uzun olsun.';
    await tester.enterText(find.byKey(const Key('message')), message);
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    double bubbleWidth() => tester
        .getSize(find.ancestor(of: find.text(message), matching: find.byType(Container)).first)
        .width;
    final bubble = bubbleWidth();
    expect(bubble, greaterThan(560));
    expect(tester.getSize(find.byKey(const Key('message'))).width, lessThanOrEqualTo(Layout.chat));
    // A short message shows the character cap moving with the text scale.
    const short = 'Kitaplari rafa koy';
    await tester.enterText(find.byKey(const Key('message')), short);
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    double shortWidth() => tester
        .getSize(find.ancestor(of: find.text(short), matching: find.byType(Container)).first)
        .width;
    final shortBefore = shortWidth();
    for (var i = 0; i < 10; i++) {
      session.zoomChatIn();
    }
    await tester.pumpAndSettle();
    expect(shortWidth(), greaterThan(shortBefore));
  });

  testWidgets('chat on a phone keeps its bubble gutter (#697)', (tester) async {
    phone(tester);
    await pumpApp(tester, Harness(answers: ['Saved.']));
    await connect(tester, key: 'k');
    const message =
        'Kitaplari rafa koy ve haftaya dentist randevusunu hatirlat, sonra da kutuphane icin yeni bir proje notu ac ve icini doldur, boylece satirlar dolacak kadar uzun olsun.';
    await tester.enterText(find.byKey(const Key('message')), message);
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    final bubble = tester
        .getSize(find.ancestor(of: find.text(message), matching: find.byType(Container)).first)
        .width;
    final window = tester.getSize(find.byType(MaterialApp)).width;
    expect(bubble, lessThanOrEqualTo(window * 0.85 + 0.5));
  });

  testWidgets('chat on a wide window: the composer and examples share the conversation (#771)', (
    tester,
  ) async {
    desktop(tester, 1400);
    await pumpApp(tester, Harness(answers: ['Saved.']));
    await connect(tester, key: 'k');
    final field = tester.getSize(find.byType(TextField).last).width;
    expect(field, greaterThan(Layout.column));
    expect(field, lessThanOrEqualTo(Layout.chat));
    expect(tester.getSize(find.byType(OutlinedButton).last).width, greaterThan(Layout.column));
    const long =
        'Kitaplari rafa koy ve haftaya dentist randevusunu hatirlat, sonra da kutuphane icin yeni bir proje notu ac ve icini doldur, boylece satirlar dolacak kadar uzun olsun.';
    await tester.enterText(find.byKey(const Key('message')), long);
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.text(long)).width, greaterThan(560));
  });
  testWidgets('desktop: the sync state sits at the foot of the compact rail (#774)', (
    tester,
  ) async {
    desktop(tester, 1000);
    final harness = Harness(auth: FakeAuth()..granted = true);
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await session.connectDrive();
    await tester.pumpAndSettle();
    expect(find.byIcon(AppIcons.cloudDone), findsOneWidget);
  });

  testWidgets('desktop: the sync state sits at the foot of the rail (#774)', (tester) async {
    desktop(tester, 1600);
    final harness = Harness(auth: FakeAuth()..granted = true);
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await session.connectDrive();
    await tester.pumpAndSettle();
    expect(find.text('Synced just now'), findsOneWidget);
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
    expect(find.byTooltip('Archive'), findsOneWidget);
    expect(find.byKey(const Key('notes-more')), findsOneWidget);
    expect(find.byTooltip('Import notes'), findsNothing);

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

  testWidgets('notes on a wide window: a related note opens in the reader (#802)', (tester) async {
    desktop(tester, 1600);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    createNote(harness.paths.notes.path, 'topic', 'Okunan kitaplar', today: today);
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitaplar'));
    await tester.pumpAndSettle();
    final reader = find.byType(NoteView);
    await tester.tap(find.descendant(of: reader, matching: find.text('Okunan kitaplar')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, 'Okunan kitaplar').first).selected,
      isTrue,
    );
    expect(
      find.descendant(of: reader, matching: find.text('Kitaplar')),
      findsOneWidget,
    ); // its related note
  });

  testWidgets('the list header lines up with the search field on a wide window (#642)', (
    tester,
  ) async {
    desktop(tester, 1600);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    final field = tester.getRect(find.byKey(const Key('notes-search')));
    final icon = tester.getRect(find.byIcon(AppIcons.moreVert));
    expect(icon.right, closeTo(field.right, 0.5));
  });

  testWidgets('notes on a wide window: Pin in the open note moves it under Pinned (#775)', (
    tester,
  ) async {
    desktop(tester, 1600);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    createNote(harness.paths.notes.path, 'topic', 'Filmler', today: today);
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitaplar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pin'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Unpin'), findsOneWidget);
    expect(find.text('PINNED'), findsOneWidget);
    await tester.tap(find.byTooltip('Unpin'));
    await tester.pumpAndSettle();
    expect(find.text('PINNED'), findsNothing);
  });

  testWidgets('notes on a wide window: a todo checkbox writes the note (#512)', (tester) async {
    desktop(tester, 1600);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    final path = createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    addTodo(path, 'Return the book', today: today);
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitaplar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.pump();
    expect(File(path).readAsStringSync(), contains('- [x] '));
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

    // Archived elsewhere: the empty state takes the window.
    await session.deleteNote(session.listNotes().single);
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('No notes yet. Tell the assistant something to remember.'), findsOneWidget);
    expect(find.text('Pick a note to read it here.'), findsNothing);
  });

  testWidgets('with a hardware keyboard, Enter sends and the box keeps the focus (#497)', (
    tester,
  ) async {
    desktop(tester, 1600); // no on-screen keyboard: a desktop, or a tablet with a keyboard
    final harness = Harness(answers: ['Tamam.']);
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await tester.enterText(find.byKey(const Key('message')), 'selam');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(harness.provider.asked, ['selam']);
    expect(tester.testTextInput.isVisible, isTrue); // the next message needs no click
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

  testWidgets('an empty wide notes screen keeps one empty state (#555)', (tester) async {
    desktop(tester, 1600);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('No notes yet. Tell the assistant something to remember.'), findsOneWidget);
    expect(find.text('Pick a note to read it here.'), findsNothing);
    expect(find.byKey(const Key('notes-more')), findsOneWidget);
    await tester.tap(find.byTooltip('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('The archive is empty. Deleted notes go here.'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('No notes yet. Tell the assistant something to remember.'), findsOneWidget);
    expect(find.text('The archive is empty. Deleted notes go here.'), findsNothing);
  });

  testWidgets('the archive opens beside the rail, at a readable width (#508)', (tester) async {
    desktop(tester, 1600);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Archive'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(
      tester.getSize(find.text('The archive is empty. Deleted notes go here.')).width,
      lessThanOrEqualTo(Layout.column),
    );
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Kitaplar'), findsOneWidget);
    // An archived note reads in the pane too; Back and the system's back step out.
    await tester.tap(find.text('Kitaplar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Archive'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitaplar'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Restore'), findsNothing); // the archive's list again
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Archive'), findsOneWidget); // back in the notes
  });

  testWidgets('settings: the pane is centred and Usage keeps the rail (#715)', (tester) async {
    desktop(tester, 1600);
    await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    // The readable column is centred in the pane, not at its left edge.
    expect(tester.getTopLeft(find.text('Model in use')).dx, greaterThan(400));
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-usage')));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('14 days'), findsOneWidget); // the usage view, in the pane
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('open-usage')), findsOneWidget); // the section again
  });

  testWidgets('settings: the chat text size control keeps its width on a desktop (#716)', (
    tester,
  ) async {
    desktop(tester, 1600);
    await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    await openSettings(tester, 'Appearance');
    final smaller = tester.getCenter(find.byTooltip('Smaller text'));
    final larger = tester.getCenter(find.byTooltip('Larger text'));
    expect(larger.dx - smaller.dx, lessThan(140));
  });

  testWidgets('chat: the working status reads at body size on a desktop (#723)', (tester) async {
    desktop(tester, 1600);
    await pumpApp(tester, Harness(answers: [Completer<AgentResponse>().future]));
    await connect(tester, key: 'k');
    await tester.enterText(find.byKey(const Key('message')), 'selam');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    final status = find.byKey(const Key('working'));
    final text = tester.widget<Text>(
      find.descendant(of: status, matching: find.byType(Text)).first,
    );
    expect(text.style!.fontSize!, greaterThan(12)); // bodyMedium, not bodySmall
    final spinner = tester.getSize(
      find.descendant(of: status, matching: find.byType(CircularProgressIndicator)),
    );
    expect(spinner.width, greaterThanOrEqualTo(16));
    await tester.tap(find.byTooltip('Stop the answer'));
    await tester.pumpAndSettle();
  });

  testWidgets('the rail: the brand label, the chosen item on a card, the sync at its foot (#782)', (
    tester,
  ) async {
    desktop(tester, 1600);
    await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    final theme = Theme.of(tester.element(find.byType(NavigationRail)));
    expect(rail.backgroundColor, Colors.transparent); // the night's glow shows through
    expect(rail.useIndicator, isTrue);
    expect(rail.indicatorColor, theme.colorScheme.surfaceContainerLow);
    expect(
      (rail.indicatorShape! as RoundedRectangleBorder).side.color,
      theme.colorScheme.outlineVariant,
    );
    expect(rail.trailingAtBottom, isTrue);
    final label = theme.extension<NoteloreTokens>()!.label;
    expect(tester.widget<Text>(find.text('Notelore')).style!.fontFamily, label.fontFamily);
  });
}
