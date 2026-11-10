import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/icons.dart';
import 'package:notelore/src/note_view.dart';
import 'package:notelore/src/section_label.dart';
import 'package:notelore/src/strings.dart';
import 'package:notelore/src/theme.dart';
import 'package:notelore_core/notelore_core.dart';

const _mopsos = '''---
title: Mopsos
kind: project
created: 2026-09-12
updated: 2026-10-18
tags: [investing, side-project]
---
# Mopsos

Stock picks, scored weekly.

## Decisions
- ~~2026-09-12 — **database**: PostgreSQL.~~ _(superseded 2026-09-28)_
- 2026-09-28 — **database**: SQLite. Single user, zero setup.
- 2026-09-20 — **frontend**: React + Vite.

## Notes
- 2026-09-15: Prediction hit rate is calculated **weekly**, on Sundays.
- 2026-09-22: Considered adding crypto,
  postponed until the stock flow is stable.

## Todo
- [x] 2026-09-25: Set up CI
- [ ] 2026-10-15: Add Drive backup
- [ ] 2026-11-02: Write the README

## Links
- [Broker API](https://example.com/api)
''';

Future<void> show(
  WidgetTester tester,
  String source, {
  Strings? strings,
  void Function(int number, String text, bool done)? onTodo,
  List<NoteInfo> related = const [],
  ValueChanged<NoteInfo>? onOpen,
}) async {
  // Tall enough that the whole note is laid out.
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: noteloreTheme(Brightness.light),
      home: Scaffold(
        body: NoteView(
          source,
          folder: '/notes/projects',
          strings: strings ?? EnglishStrings(),
          today: DateTime(2026, 10, 19),
          onTodo: onTodo,
          related: related,
          onOpen: onOpen,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a note reads as a page: title, kind and tags, when it changed (#426)', (
    tester,
  ) async {
    await show(tester, _mopsos);
    expect(find.text('Mopsos'), findsOneWidget);
    expect(find.text('Project'), findsOneWidget);
    expect(find.text('#investing #side-project  ·  Updated 18 Oct'), findsOneWidget);
    expect(find.text('Stock picks, scored weekly.'), findsOneWidget);
  });

  testWidgets('a section with nothing in it shows no heading (#508)', (tester) async {
    await show(tester, '$_mopsos\n## Questions\n\n');
    expect(find.text('QUESTIONS'), findsNothing);
    expect(find.text('LINKS'), findsOneWidget); // one with something in it still has its own
  });

  testWidgets('decisions: the current ones as cards, earlier ones folded away (#426)', (
    tester,
  ) async {
    await show(tester, _mopsos);
    expect(find.text('DECISIONS'), findsOneWidget);
    expect(find.text('DATABASE'), findsOneWidget);
    expect(find.text('SQLite'), findsOneWidget);
    expect(find.text('Single user, zero setup.'), findsOneWidget);
    expect(find.text('React + Vite'), findsOneWidget);
    expect(find.text('PostgreSQL'), findsNothing);
    await tester.tap(find.text('Earlier decisions (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('PostgreSQL', findRichText: true), findsOneWidget);
    expect(find.textContaining('superseded 28 Sep', findRichText: true), findsOneWidget);
  });

  testWidgets('todos: open ones by date with the late ones marked, done ones last (#426)', (
    tester,
  ) async {
    await show(tester, _mopsos);
    final order = [
      for (final text in ['Add Drive backup', 'Write the README', 'Set up CI'])
        tester.getTopLeft(find.text(text)).dy,
    ];
    expect(order, orderedEquals([...order]..sort()));
    expect(find.byIcon(AppIcons.unchecked), findsNWidgets(2));
    expect(find.byIcon(AppIcons.checked), findsOneWidget);
    expect(find.text('Overdue, 15 Oct'), findsOneWidget);
    expect(find.text('2 Nov'), findsOneWidget);
  });

  testWidgets('todos are real checkboxes when the reader can write them (#512)', (tester) async {
    final tapped = <(int, bool)>[];
    await show(tester, _mopsos, onTodo: (number, text, done) => tapped.add((number, done)));
    final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
    // Open ones by date first, the done one last: their number is the file's.
    expect(boxes.map((b) => b.value), [false, false, true]);
    await tester.tap(find.byType(Checkbox).first);
    await tester.tap(find.byType(Checkbox).last);
    expect(tapped, [(2, true), (1, false)]);
  });

  testWidgets('todos: a checkbox is centred on its title (#710)', (tester) async {
    await show(tester, _mopsos, onTodo: (_, _, _) {});
    final box = tester.getCenter(find.byType(Checkbox).first);
    final title = tester.getCenter(find.text('Add Drive backup'));
    expect((box.dy - title.dy).abs(), lessThanOrEqualTo(2.5));
  });

  testWidgets('todos and reminders: one 16 dp edge, text at 42, 48 dp rows (#852)', (tester) async {
    const source = '''---
title: Passport
kind: topic
---
# Passport

## Todo
- [ ] 2026-10-25: Fill in the form
- [ ] 2026-10-26: Pay the fee

## Reminders
- 2026-10-21: Book the photos
- 2026-11-03 09:30: Passport office
''';
    for (final onTodo in [null, (int _, String _, bool _) {}]) {
      await show(tester, source, onTodo: onTodo);
      double left(String text) => tester.getTopLeft(find.text(text, findRichText: true)).dx;
      double top(String text) => tester.getTopLeft(find.text(text, findRichText: true)).dy;
      for (final text in [
        'Fill in the form',
        'Pay the fee',
        'Book the photos',
        'Passport office',
      ]) {
        expect(left(text), 42, reason: text);
      }
      expect(tester.getTopLeft(find.byIcon(AppIcons.notifications).first).dx, Gap.m);
      if (onTodo != null) {
        // The 18 dp square a Checkbox paints sits in the middle of its box.
        expect(tester.getCenter(find.byType(Checkbox).first).dx - 9, Gap.m);
      }
      expect(top('Pay the fee') - top('Fill in the form'), greaterThanOrEqualTo(48));
      expect(top('Passport office') - top('Book the photos'), greaterThanOrEqualTo(48));
    }
  });

  testWidgets('todos: a wrapped one keeps the space below it that a short one has (#852)', (
    tester,
  ) async {
    await show(tester, '''---
title: Passport
kind: topic
---
# Passport

## Todo
- [ ] 2026-10-25: ${'Pay the fee at the bank with the reference number. ' * 8}
- [ ] 2026-10-26: Short one
- [ ] 2026-10-27: Last one
''', onTodo: (_, _, _) {});
    final wrapped = find.textContaining('Pay the fee', findRichText: true);
    expect(tester.getSize(wrapped).height, greaterThan(40));
    final next = tester.getTopLeft(find.text('Short one', findRichText: true)).dy;
    // 12 dp under it and 12 above the next one, close to a short row's 16 + 12.
    expect(next - tester.getBottomLeft(wrapped).dy, 24);
  });

  testWidgets('todos: a read-only mark is as wide as a reminder icon (#852)', (tester) async {
    await show(tester, _mopsos);
    expect(tester.getSize(find.byIcon(AppIcons.unchecked).first).width, 18);
  });

  testWidgets('todos: the checkbox still takes a tap beside its square (#852)', (tester) async {
    final tapped = <int>[];
    await show(tester, _mopsos, onTodo: (number, _, _) => tapped.add(number));
    final box = tester.getCenter(find.byType(Checkbox).first);
    await tester.tapAt(Offset(Gap.m + 22, box.dy + 20));
    expect(tapped, [2]);
  });

  testWidgets('the page ends with room above the system bar (#852)', (tester) async {
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    await show(tester, _mopsos);
    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.padding?.resolve(TextDirection.ltr).bottom, Gap.l + 34);
  });

  testWidgets('reminders: with the todos above the notes, coming ones first (#430)', (
    tester,
  ) async {
    await show(tester, '''---
title: Passport
kind: topic
---
# Passport

## Notes
- 2026-10-01: The old one expires in December.

## Todo
- [ ] 2026-10-25: Fill in the form

## Reminders
- 2026-10-02: Find the old passport
- 2026-10-15 18:00: Ask Ali about the studio
- 2026-11-03 09:30: Passport office
- 2026-10-21: Book the photos
- not a reminder, as written
''');
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    // What is coming (reminders, then todos) before what happened.
    expect([
      top('REMINDERS'),
      top('TODO'),
      top('NOTES'),
    ], orderedEquals([top('REMINDERS'), top('TODO'), top('NOTES')]..sort()));
    // Coming ones by day and time, then past ones, the latest first.
    final rows = [
      'Book the photos',
      'Passport office',
      'Ask Ali about the studio',
      'Find the old passport',
    ];
    final tops = [for (final row in rows) top(row)];
    expect(tops, orderedEquals([...tops]..sort()));
    // Every date in one column, at the right edge.
    expect(
      tester.getTopRight(find.text('21 Oct')).dx,
      tester.getTopRight(find.text('3 Nov · 09:30')).dx,
    );
    expect(tester.getTopRight(find.text('25 Oct')).dx, tester.getTopRight(find.text('21 Oct')).dx);
    expect(find.text('21 Oct'), findsOneWidget);
    expect(find.text('3 Nov · 09:30'), findsOneWidget);
    // A past one says so in words and with its own icon, not by colour alone.
    expect(find.text('Passed, 15 Oct · 18:00'), findsOneWidget);
    expect(find.byIcon(AppIcons.notifications), findsNWidgets(2));
    expect(find.byIcon(AppIcons.history), findsNWidgets(2));
    expect(find.text('not a reminder, as written'), findsOneWidget);
  });

  testWidgets('notes: a timeline, newest first, its words formatted (#426)', (tester) async {
    await show(tester, _mopsos);
    final crypto = tester.getTopLeft(find.textContaining('Considered adding crypto')).dy;
    final weekly = tester.getTopLeft(find.textContaining('Prediction hit rate')).dy;
    expect(crypto, lessThan(weekly));
    expect(find.textContaining('postponed until the stock flow is stable'), findsOneWidget);
    expect(find.text('22 Sep'), findsOneWidget);
    // A section the person wrote by hand shows as written.
    expect(find.text('LINKS'), findsOneWidget);
    expect(find.text('Broker API'), findsOneWidget);
  });

  testWidgets('no kind, no pill; a value in Markdown; days by their date (#426)', (tester) async {
    await show(
      tester,
      '---\ntitle: Loose\n---\n# Loose\n\n## Decisions\n- 2026-10-01 — **host**: **Fly.io**.\n\n'
      '## Notes\n- 2026-10-02: Later one.\n- 2026-09-01: Earlier, written below.\n',
    );
    expect(find.text('null'), findsNothing);
    expect(find.text('Fly.io', findRichText: true), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Later one.', findRichText: true)).dy,
      lessThan(tester.getTopLeft(find.text('Earlier, written below.', findRichText: true)).dy),
    );
  });

  testWidgets('a file that is not a note shows as Markdown; Turkish dates (#426)', (tester) async {
    await show(tester, '# Just a page\n\nHello.\n');
    expect(find.text('Just a page'), findsOneWidget);
    expect(find.text('Hello.'), findsOneWidget);
    tester.widget<Markdown>(find.byType(Markdown)).onTapLink!('none', null, ''); // opens nothing
    await show(
      tester,
      _mopsos
          .replaceFirst('updated: 2026-10-18', 'updated: 2025-01-05')
          .replaceFirst('- 2026-09-15: Prediction', '- 2025-09-15: Prediction'),
      strings: TurkishStrings(),
    );
    expect(find.text('Proje'), findsOneWidget);
    expect(find.text('#investing #side-project  ·  Güncellendi 5 Oca 2025'), findsOneWidget);
    // An older year heads its days once; the days themselves carry no year.
    expect(find.text('2025'), findsOneWidget);
    expect(find.text('15 Eyl'), findsOneWidget);
    expect(find.text('Önceki kararlar (1)'), findsOneWidget);
  });

  testWidgets('related notes: cards at the foot that open their note (#802)', (tester) async {
    final opened = <NoteInfo>[];
    final related = [
      NoteInfo('mopsos-launch', 'topic', 'Mopsos launch', DateTime(2026, 10, 2)),
      const NoteInfo('garden', 'project', 'Garden', null, tags: ['investing']),
    ];
    await show(tester, _mopsos, related: related, onOpen: opened.add);
    final heading = find.widgetWithText(SectionLabel, 'RELATED NOTES');
    expect(heading, findsOneWidget);
    expect(find.text('Mopsos launch'), findsOneWidget);
    expect(find.text('Topic · updated 2 Oct'), findsOneWidget);
    expect(find.text('Project · updated ? · #investing'), findsOneWidget);
    // Below everything the note says.
    expect(
      tester.getTopLeft(heading).dy,
      greaterThan(tester.getTopLeft(find.text('Broker API', findRichText: true)).dy),
    );
    await tester.tap(find.text('Garden'));
    expect(opened, [related[1]]);

    await show(tester, _mopsos, related: related);
    expect(heading, findsNothing); // nowhere to open them
    await show(tester, _mopsos, onOpen: opened.add);
    expect(heading, findsNothing); // none
    await show(tester, _mopsos, related: related, onOpen: opened.add, strings: TurkishStrings());
    expect(find.widgetWithText(SectionLabel, 'İLGİLİ NOTLAR'), findsOneWidget);
  });
}
