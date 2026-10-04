import 'dart:io';

import 'package:notelore_core/src/store/notes.dart';
import 'package:notelore_core/src/store/stale.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/files.dart';

DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);
final today = d(2026, 9, 30);

void main() {
  late String root;
  setUp(() {
    root = p.join(tempDir(), 'notes');
    final mopsos = createNote(root, 'project', 'Mopsos', today: d(2026, 1, 1));
    recordDecision(mopsos, 'database', 'PostgreSQL', today: d(2026, 1, 5));
    recordDecision(mopsos, 'database', 'SQLite', today: d(2026, 3, 1)); // supersedes: old
    recordDecision(mopsos, 'hosting', 'Fly', today: d(2026, 9, 1));
    recordDecision(mopsos, 'hosting', 'Hetzner', today: d(2026, 9, 20)); // recent
    // a stray hand-written line must not shift numbers
    atomicWrite(mopsos, read(mopsos).replaceFirst('## Decisions\n', '## Decisions\nstray line\n'));
    addTodo(mopsos, 'Overdue', due: d(2026, 9, 1), today: d(2026, 8, 1));
    addTodo(mopsos, 'Done long ago', due: d(2026, 2, 1), today: d(2026, 2, 1));
    completeTodo(mopsos, 2, today: d(2026, 2, 1));
    addTodo(mopsos, 'Future', due: d(2026, 12, 1), today: today);
    final fresh = createNote(root, 'topic', 'Fresh', today: today);
    addTodo(fresh, 'Due today is not overdue', due: today, today: today);
    final old = createNote(root, 'topic', 'Untouched', today: d(2026, 1, 1));
    addEntry(old, 'written once', today: d(2026, 1, 2));
    File(p.join(root, 'topics', 'not-a-note.md')).writeAsStringSync('plain\n');
    // no sections, unparsable updated: never stale
    File(p.join(root, 'topics', 'bare.md')).writeAsStringSync(
      '---\ntitle: Bare\nkind: topic\ncreated: 2026-01-01\nupdated: soon\n---\n# Bare\n',
    );
    createNote(p.join(root, '_archive', '2026-01-01'), 'project', 'Archived', today: d(2026, 1, 1));
  });

  test('signals', () {
    expect(findStaleNotes(root, today: today), [
      Stale('mopsos', 'project', 'superseded decision', 'decisions', 1, d(2026, 3, 1)),
      Stale('mopsos', 'project', 'overdue todo', 'todo', 1, d(2026, 9, 1)),
      Stale('untouched', 'topic', 'not updated', null, null, d(2026, 1, 2)),
    ]);
  });

  test('thresholds are tunable', () {
    final stale = findStaleNotes(root, today: today, decisionDays: 5, fileDays: 5);
    expect(stale.map((s) => (s.slug, s.reason, s.number)), [
      ('mopsos', 'superseded decision', 1),
      ('mopsos', 'superseded decision', 3),
      ('mopsos', 'overdue todo', 1),
      ('untouched', 'not updated', null),
    ]);
    expect(findStaleNotes(root, today: d(2027, 12, 1), fileDays: 10000), [
      Stale('mopsos', 'project', 'superseded decision', 'decisions', 1, d(2026, 3, 1)),
      Stale('mopsos', 'project', 'superseded decision', 'decisions', 3, d(2026, 9, 20)),
      Stale('mopsos', 'project', 'overdue todo', 'todo', 1, d(2026, 9, 1)),
      Stale('mopsos', 'project', 'overdue todo', 'todo', 3, d(2026, 12, 1)),
      Stale('fresh', 'topic', 'overdue todo', 'todo', 1, today),
    ]);
  });

  test('numbers match archiveEntries', () {
    final decision = findStaleNotes(root, today: today).first;
    final path = notePath(root, decision.kind, decision.slug);
    archiveEntries(root, path, {
      decision.section!: [decision.number!],
    }, today: today);
    expect(read(path), isNot(contains('PostgreSQL')));
  });

  test('an empty folder and today by default', () {
    expect(findStaleNotes(p.join(root, 'nothing')), isEmpty);
    expect(findStaleNotes(root), isNotEmpty);
  });

  test('a file that is not UTF-8 is a real error, not hidden', () {
    File(p.join(root, 'topics', 'latin1.md')).writeAsBytesSync([0x63, 0x61, 0x66, 0xE9]);
    expect(() => findStaleNotes(root, today: today), throwsA(isA<FileSystemException>()));
  });

  test('values compare by value', () {
    final stale = Stale('a', 'topic', 'not updated', null, null, today);
    expect(stale.hashCode, Stale('a', 'topic', 'not updated', null, null, today).hashCode);
    expect(stale, isNot(Stale('a', 'topic', 'not updated', null, 1, today)));
    expect('$stale', contains('not updated'));
  });
}
