import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/note_view.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;

import 'app_test.dart' show connect, phone, pumpApp;
import 'support.dart';

void main() {
  final now = DateTime(2026, 10, 19, 9);
  DateTime day(int d) => DateTime.utc(2026, 10, d);

  Future<Harness> withPlans(WidgetTester tester) async {
    final harness = Harness();
    await pumpApp(tester, harness, clock: () => now);
    await connect(tester, key: 'k');
    final root = harness.paths.notes.path;
    final health = createNote(root, 'topic', 'Health', today: day(1));
    addReminder(health, 'Dentist', day(20), time: '10:00', today: day(1));
    final shed = createNote(root, 'project', 'Garden Shed', today: day(1));
    addTodo(shed, 'Paint the door', due: day(25), today: day(1));
    addTodo(shed, 'Order timber', due: day(10), today: day(1));
    return harness;
  }

  testWidgets('calendar: what is coming, late todos first, a tap opens the note (#453)', (
    tester,
  ) async {
    phone(tester);
    final harness = await withPlans(tester);
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);
    final order = [
      for (final text in ['Overdue', 'Order timber', 'Tomorrow', 'Dentist', 'Paint the door'])
        tester.getTopLeft(find.text(text).last).dy,
    ];
    expect(order, orderedEquals([...order]..sort()));
    expect(find.text('10 Oct · Garden Shed'), findsOneWidget); // under Overdue, said once
    expect(find.text('10:00 · Health'), findsOneWidget);
    expect(find.text('Sunday, 25 October'), findsOneWidget);
    // A note gone since the list was drawn: nothing opens, the list is drawn again.
    File(p.join(harness.paths.notes.path, 'projects', 'garden-shed.md')).deleteSync();
    await tester.tap(find.text('Paint the door'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteView), findsNothing);
    expect(find.text('Paint the door'), findsNothing);
    await tester.tap(find.text('Dentist'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteView), findsOneWidget);
    expect(find.text('Health'), findsWidgets);
  });

  testWidgets('calendar: a todo checkbox completes it and it leaves the list (#512)', (
    tester,
  ) async {
    phone(tester);
    final harness = await withPlans(tester);
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNWidgets(2));
    await tester.tap(find.byType(Checkbox).first); // Order timber, under Overdue
    await tester.pumpAndSettle();
    expect(find.text('Order timber'), findsNothing);
    expect(find.byType(Checkbox), findsOneWidget);
    final file = File(p.join(harness.paths.notes.path, 'projects', 'garden-shed.md'))
        .readAsStringSync();
    expect(file, contains('- [x] 2026-10-10: Order timber'));
  });

  testWidgets('calendar: a day picked shows its things; another month; nothing yet (#453)', (
    tester,
  ) async {
    phone(tester);
    await withPlans(tester);
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Sunday, 25 October'));
    await tester.pumpAndSettle();
    expect(find.text('Sunday, 25 October'), findsWidgets);
    expect(find.text('Paint the door'), findsOneWidget);
    expect(find.text('Dentist'), findsNothing);
    // A day with nothing on it.
    await tester.tap(find.bySemanticsLabel('Thursday, 22 October'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing on this day.'), findsOneWidget);
    // A late day picked says it is late, as there is no Overdue heading there.
    await tester.tap(find.bySemanticsLabel('Saturday, 10 October'));
    await tester.pumpAndSettle();
    expect(find.text('Overdue, 10 Oct · Garden Shed'), findsOneWidget);
    // Show all, or the same day again: back to what is coming.
    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();
    expect(find.text('Dentist'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Tuesday, 20 October'));
    await tester.pumpAndSettle();
    expect(find.text('Show all'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Tuesday, 20 October'));
    await tester.pumpAndSettle();
    expect(find.text('Show all'), findsNothing);
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('November 2026'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('September 2026'), findsOneWidget);
    // Today brings the month back.
    await tester.tap(find.byTooltip('Today'));
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);
  });

  testWidgets('calendar: reminder and todo titles share one edge (#711)', (tester) async {
    phone(tester);
    await withPlans(tester);
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    final reminder = tester.getTopLeft(find.text('Dentist'));
    final todo = tester.getTopLeft(find.text('Paint the door'));
    expect(reminder.dx, closeTo(todo.dx, 0.5));
  });

  testWidgets('calendar: at 2x text the grid does not overflow and a day is 48 (#705)', (
    tester,
  ) async {
    phone(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await withPlans(tester);
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final day = find
        .bySemanticsLabel(RegExp(r'^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday), '))
        .first;
    final size = tester.getSize(day);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });
  testWidgets('calendar: a day fits a narrow cell at 2x text (#705)', (tester) async {
    phone(tester);
    tester.view.physicalSize = const Size(900, 2400); // 360 dp: a cell is under 48 dp
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await withPlans(tester);
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    final cell = tester.getSize(
      find
          .bySemanticsLabel(
            RegExp(r'^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday), '),
          )
          .first,
    );
    expect(cell.width, lessThan(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('calendar: empty, it says where things come from; a wide window side by side', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1280, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester, Harness(), clock: () => now);
    await connect(tester, key: 'k');
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing planned'), findsOneWidget);
    expect(find.byType(VerticalDivider), findsWidgets);
    // The way to make one: the chat.
    await tester.tap(find.text('Go to chat'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message')), findsOneWidget);
  });
}
