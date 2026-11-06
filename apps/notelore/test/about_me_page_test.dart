import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/about_me_page.dart';
import 'package:notelore_core/notelore_core.dart';

import 'app_test.dart' show connect, phone, pumpApp;
import 'desktop_test.dart' show desktop;
import 'support.dart';

void main() {
  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const Key('fact-field')), text);
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
  }

  testWidgets('about me: say what it is, add, edit and delete facts, undo (#646)', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await session.setAboutMeToCloud(false); // a cloud model, so the button is the way
    // A place of its own in the bottom bar, beside Notes and Calendar (#669).
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    await tester.tap(find.text('About me'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Tell the assistant about yourself'), findsOneWidget);

    await tester.tap(find.text('Add a fact'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const Key('fact-field')), 'Wife: Ayşe');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done); // Enter saves too
    await tester.pumpAndSettle();
    expect(find.text('Wife: Ayşe'), findsOneWidget);
    expect(find.textContaining('Tell the assistant about yourself'), findsNothing);

    // The same fact twice: said by the field, the dialog stays open.
    await tester.tap(find.text('Add a fact'));
    await tester.pumpAndSettle();
    await type(tester, 'wife: ayşe');
    expect(find.text('This is already in the list.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Wife: Ayşe'));
    await tester.pumpAndSettle();
    // A long fact wraps while it is edited, so all of it can be read.
    expect(tester.widget<TextField>(find.byKey(const Key('fact-field'))).maxLines, 6);
    expect(find.widgetWithText(TextField, 'Wife: Ayşe'), findsOneWidget);
    await type(tester, 'Wife: Ayşe Yılmaz');
    expect(session.aboutMeFacts(), ['Wife: Ayşe Yılmaz']);

    expect(tester.getSize(find.byTooltip('Delete')).height, greaterThanOrEqualTo(48));
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(session.aboutMeFacts(), isEmpty);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(session.aboutMeFacts(), ['Wife: Ayşe Yılmaz']);
    await tester.pumpAndSettle(const Duration(seconds: 10)); // the snackbar goes

    // Deleted elsewhere first: the tap only catches up.
    forgetAboutMe(harness.paths.notes.path, 'Wife: Ayşe Yılmaz');
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Wife: Ayşe Yılmaz'), findsNothing);
    expect(find.text('Undo'), findsNothing);

    // Changed elsewhere (a sync): the page follows.
    rememberAboutMe(harness.paths.notes.path, 'Lives in Izmir');
    session.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Lives in Izmir'), findsOneWidget);

    // A fact gone elsewhere before the edit is saved: said, nothing written.
    await tester.tap(find.text('Lives in Izmir'));
    await tester.pumpAndSettle();
    File(aboutMePath(harness.paths.notes.path)).writeAsStringSync('# About me\n');
    await type(tester, 'Lives in Ankara');
    expect(find.text('This changed on another device. Close and try again.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // The cloud switch stays a setting: the page links to it (#669).
    await tester.scrollUntilVisible(find.text('Kept from cloud models'), 200);
    await tester.tap(find.text('Kept from cloud models'));
    await tester.pumpAndSettle();
    expect(find.text('Privacy'), findsOneWidget); // the settings page
    await tester.tap(find.text('Share with cloud models'));
    await tester.pumpAndSettle();
    expect(session.aboutMeToCloud, isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Shared with cloud models'), findsOneWidget);
    expect(find.text('Add a fact'), findsNothing); // the chat keeps them now (#749)
  });

  testWidgets('about me: facts under their sections; add and edit pick one (#671)', (tester) async {
    phone(tester);
    final session = await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    await session.setAboutMeToCloud(false); // a cloud model, so the button is the way
    await tester.tap(find.text('About me'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add a fact'));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Other')).selected, isTrue);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Family'));
    await tester.pump();
    await type(tester, 'Wife: Ayşe');
    await tester.tap(find.text('Add a fact'));
    await tester.pumpAndSettle();
    await type(tester, 'Likes tea');
    expect(find.text('FAMILY'), findsOneWidget); // a section header
    expect(find.text('OTHER'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Wife: Ayşe')).dy,
      greaterThan(tester.getTopLeft(find.text('FAMILY')).dy),
    );

    // Editing shows its section and can move it.
    await tester.tap(find.text('Wife: Ayşe'));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Family')).selected, isTrue);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Home'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(session.aboutMeEntries().first, (section: 'other', fact: 'Likes tea'));
    expect(session.aboutMeEntries(), contains((section: 'home', fact: 'Wife: Ayşe')));
    expect(find.text('FAMILY'), findsNothing);

    // The undo after a delete never covers the add button.
    await tester.tap(find.byTooltip('Delete').first);
    await tester.pump(const Duration(milliseconds: 750));
    // Shown by the page's own scaffold, which keeps it clear of the button.
    expect(
      find.descendant(of: find.byType(AboutMeScreen), matching: find.byType(SnackBar)),
      findsOneWidget,
    );
    final button = tester.getRect(find.byType(FloatingActionButton));
    final undo = tester.getRect(find.byType(SnackBar));
    expect(button.overlaps(undo), isFalse);
  });

  testWidgets('about me: the last row clears the add button at 2x (#719)', (tester) async {
    phone(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final session = await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    await session.setAboutMeToCloud(false);
    for (var i = 0; i < 8; i++) {
      await session.rememberFact('Fact number $i');
    }
    await tester.tap(find.text('About me'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Kept from cloud models'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final row = tester.getRect(
      find.ancestor(of: find.text('Kept from cloud models'), matching: find.byType(ListTile)),
    );
    expect(row.overlaps(tester.getRect(find.byType(FloatingActionButton))), isFalse);
  });

  testWidgets('about me: no add button when the chat keeps the facts (#749)', (tester) async {
    phone(tester);
    final session = await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    await session.setAboutMeToCloud(true);
    await tester.tap(find.text('About me'));
    await tester.pumpAndSettle();
    // Empty, the way to fill it is the chat.
    await tester.tap(find.text('Go to chat'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutMeScreen), findsNothing);
    await session.rememberFact('Likes tea');
    await tester.tap(find.text('About me'));
    await tester.pumpAndSettle();
    expect(find.text('Go to chat'), findsNothing);
    expect(find.text('Add a fact'), findsNothing);
    expect(find.byTooltip('Delete'), findsOneWidget);
    await tester.tap(find.text('Likes tea')); // a fact can still be corrected by hand
    await tester.pumpAndSettle();
    await type(tester, 'Likes green tea');
    expect(session.aboutMeFacts(), ['Likes green tea']);

    // Kept from a cloud model, the chat cannot add one: the button is the way.
    await session.setAboutMeToCloud(false);
    await tester.pumpAndSettle();
    expect(find.text('Add a fact'), findsOneWidget);
  });

  testWidgets('about me: in the side rail on a wide window; Settings keeps Privacy', (
    tester,
  ) async {
    desktop(tester, 1280);
    final session = await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    await session.setAboutMeToCloud(false); // a cloud model, so the button is the way
    await tester.tap(find.text('About me'));
    await tester.pumpAndSettle();
    expect(find.text('Add a fact'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing); // by the list, not a far corner
    await tester.tap(find.text('Add a fact'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fact-field')), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await openSettings(tester, 'Privacy');
    expect(find.text('Share with cloud models'), findsOneWidget);
    expect(find.text('Add a fact'), findsNothing);
  });
}
