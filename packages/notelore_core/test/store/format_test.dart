import 'dart:convert';

import 'package:notelore_core/src/store/format.dart';
import 'package:test/test.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../support/spec.dart';

DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

void main() {
  final fixtures = fixtureBytes();
  final mopsos = utf8.decode(fixtures['mopsos.md']!);
  String fixture(String name) => utf8.decode(fixtures[name]!);

  group('round trip is byte identical', () {
    for (final MapEntry(key: name, value: raw) in fixtures.entries) {
      test(name, () {
        final text = utf8.decode(raw);
        // CRLF input is normalized to LF on parse.
        expect(serialize(parse(text)), text.replaceAll('\r\n', '\n'));
      });
    }
  });

  test('front matter and title', () {
    final note = parse(mopsos);
    expect(note.meta['title'], 'Mopsos');
    expect(note.meta['kind'], 'project');
    expect(note.meta['created'], d(2026, 9, 12));
    expect(note.meta['updated'], d(2026, 9, 30));
    expect(note.meta['tags'], ['investing', 'side-project']);
    expect(note.title, 'Mopsos');
  });

  test('known sections are typed', () {
    final note = parse(mopsos);
    expect(note.sections.map((s) => s.key), ['decisions', 'notes', 'todo']);
    final decisions = note.section('decisions')!.entries.whereType<Decision>().toList();
    final [first, second, third] = decisions;
    expect(first, Decision(d(2026, 9, 12), 'database', 'PostgreSQL.', superseded: d(2026, 9, 28)));
    expect(first.value, 'PostgreSQL');
    expect(first.reason, isNull);
    expect(second.value, 'SQLite');
    expect(second.reason, 'Single user, zero setup.');
    expect(second.superseded, isNull);
    expect(third.topic, 'frontend');

    expect(
      note.section('notes')!.entries.first,
      Entry(d(2026, 9, 15), 'Prediction hit rate is calculated weekly, on Sundays.'),
    );
    final todo = note.section('todo')!.entries;
    expect(todo[0], Todo(d(2026, 10, 15), 'Add Drive backup'));
    expect(todo[1], Todo(d(2026, 9, 25), 'Set up CI', done: true));
  });

  test('Turkish headings map to the same keys', () {
    final note = parse(fixture('turkish.md'));
    expect(note.sections.map((s) => s.key), ['decisions', 'notes', 'todo']);
    expect(note.sections.map((s) => s.heading), ['Kararlar', 'Notlar', 'Yapılacaklar']);
    final decision = note.section('decisions')!.entries[1] as Decision;
    expect(decision.topic, 'şirket-türü');
    expect(decision.value, 'Limited şirket');
  });

  test('NFD input is normalized to NFC', () {
    final nfd = unorm.nfd(mopsos.replaceAll('Mopsos', 'Şükrü'));
    expect(nfd, isNot(contains('Şükrü')));
    final note = parse(nfd);
    expect(note.title, 'Şükrü');
    expect(serialize(note), contains('# Şükrü\n'));
  });

  test('an unknown section is kept verbatim and an empty one is empty', () {
    final note = parse(fixture('unknown-and-empty-sections.md'));
    final links = note.section('Links')!;
    expect(links.key, isNull);
    expect(links.entries.whereType<Raw>().map((e) => e.text), [
      'Hand-written section, not touched by code.',
      '- https://example.com/a',
      '- https://example.com/b',
      '',
    ]);
    expect(note.section('todo')!.entries, isEmpty);
  });

  test('continuation lines and loose lines', () {
    final note = parse(fixture('multiline-and-loose-lines.md'));
    final [os, storage] = note.section('decisions')!.entries.whereType<Decision>().toList();
    expect(os.value, 'Debian 12'); // no trailing period is tolerated
    expect(storage.text, 'ZFS mirror. Two 4 TB disks,\n  bought second hand.');
    expect(storage.value, 'ZFS mirror');
    final notes = note.section('notes')!.entries;
    expect((notes[0] as Entry).text, startsWith('Reverse proxy is Caddy'));
    expect((notes[0] as Entry).text, contains('\n  and is version controlled'));
    expect(notes[1], const Raw('Someone typed this without a bullet.'));
    final todo = note.section('todo')!.entries.first as Todo;
    expect(todo.text, 'Replace the failing fan\n  (the rear one, 120 mm)');
  });

  test('serialize writes canonical entries', () {
    final note = parse(mopsos);
    final entries = note.section('decisions')!.entries;
    entries.insert(
      entries.length - 1,
      Decision(d(2026, 9, 30), 'hosting', 'Fly.io. Cheapest region near users.'),
    );
    final out = serialize(note);
    expect(out, contains('- 2026-09-30 — **hosting**: Fly.io. Cheapest region near users.\n'));
    expect(out, endsWith('\n'));
  });

  group('not a note', () {
    final cases = {
      '# No front matter\n': 'missing YAML front matter',
      '---\n- a\n- b\n---\n# T\n': 'front matter',
      '---\njust a scalar\n---\n# T\n': 'front matter',
      '---\ntitle: [unclosed\n---\n# T\n': 'front matter',
      '---\nkind: topic\n---\n# T\n': 'front matter',
      '---\ntitle: T\n': 'unterminated',
      '---\ntitle: T\n---\n': "missing '#",
      '---\ntitle: T\n---\nno heading\n': "missing '#",
    };
    for (final MapEntry(key: text, value: reason) in cases.entries) {
      test(jsonEncode(text), () {
        expect(
          () => parse(text),
          throwsA(isA<NotANote>().having((e) => e.message, 'message', contains(reason))),
        );
      });
    }
    test('NotANote is a FormatException', () {
      expect(const NotANote('x'), isA<FormatException>());
      expect('${const NotANote('x')}', 'NotANote: x');
    });
  });

  test('an unknown section lookup returns null', () {
    expect(parse(mopsos).section('nope'), isNull);
  });

  test('unparsable bullets in known sections stay raw', () {
    const text =
        '---\ntitle: T\n---\n# T\n'
        '## Decisions\n- 2026-13-45 — **x**: bad month.\n- 0000-01-01 — **y**: year zero.\n'
        '- free bullet\n'
        '## Notes\n- [ ] 2026-09-30: todo syntax in notes\n- 2026-02-30: no such day\n'
        '## Todo\n- 2026-09-30: note syntax in todo\n';
    final note = parse(text);
    for (final key in ['decisions', 'notes', 'todo']) {
      expect(note.section(key)!.entries, everyElement(isA<Raw>()), reason: key);
    }
    expect(serialize(note), text);
  });

  test('entries compare by value and render their line', () {
    expect(Entry(d(2026, 1, 2), 'a'), Entry(d(2026, 1, 2), 'a'));
    expect(Entry(d(2026, 1, 2), 'a').hashCode, Entry(d(2026, 1, 2), 'a').hashCode);
    expect(Entry(d(2026, 1, 2), 'a'), isNot(Entry(d(2026, 1, 2), 'b')));
    expect(Todo(d(2026, 1, 2), 'a').hashCode, Todo(d(2026, 1, 2), 'a').hashCode);
    expect(Todo(d(2026, 1, 2), 'a'), isNot(Todo(d(2026, 1, 2), 'a', done: true)));
    final decision = Decision(d(2026, 1, 2), 't', 'v.');
    expect(decision.hashCode, Decision(d(2026, 1, 2), 't', 'v.').hashCode);
    expect(decision, isNot(Decision(d(2026, 1, 2), 't', 'v.', superseded: d(2026, 1, 3))));
    expect(const Raw('x').hashCode, const Raw('x').hashCode);
    expect(const Raw('x'), isNot(const Raw('y')));
    expect(
      Decision(d(2026, 1, 2), 't', 'v.', superseded: d(2026, 1, 3)).render(),
      '- ~~2026-01-02 — **t**: v.~~ _(superseded 2026-01-03)_',
    );
    expect('${Entry(d(2026, 1, 2), 'a')}', 'Entry(- 2026-01-02: a)');
  });
}
