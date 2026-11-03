import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    await openSettings(tester, 'About me');

    expect(find.textContaining('Tell the assistant about yourself'), findsOneWidget);
    expect(find.text('Send my personal info to cloud models'), findsOneWidget);

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

    await tester.tap(find.text('Send my personal info to cloud models'));
    await tester.pumpAndSettle();
    expect(session.aboutMeToCloud, isFalse);
  });

  testWidgets('about me: a category beside the others on a wide window (#646)', (tester) async {
    desktop(tester, 1280);
    await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    await openSettings(tester, 'About me');
    expect(find.text('Add a fact'), findsOneWidget);
  });
}
