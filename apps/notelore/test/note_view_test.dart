import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/note_view.dart';
import 'package:notelore/src/strings.dart';
import 'package:notelore/src/theme.dart';

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

Future<void> show(WidgetTester tester, String source, {Strings? strings}) async {
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

  testWidgets('decisions: the current ones as cards, earlier ones folded away (#426)', (
    tester,
  ) async {
    await show(tester, _mopsos);
    expect(find.text('Decisions'), findsOneWidget);
    expect(find.text('database'), findsOneWidget);
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
    expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(2));
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.text('Overdue, 15 Oct'), findsOneWidget);
    expect(find.text('2 Nov'), findsOneWidget);
  });

  testWidgets('notes: a timeline, newest first, its words formatted (#426)', (tester) async {
    await show(tester, _mopsos);
    final crypto = tester.getTopLeft(find.textContaining('Considered adding crypto')).dy;
    final weekly = tester.getTopLeft(find.textContaining('Prediction hit rate')).dy;
    expect(crypto, lessThan(weekly));
    expect(find.textContaining('postponed until the stock flow is stable'), findsOneWidget);
    expect(find.text('22 Sep'), findsOneWidget);
    // A section the person wrote by hand shows as written.
    expect(find.text('Links'), findsOneWidget);
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
}
