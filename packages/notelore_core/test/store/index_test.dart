import 'dart:io';

import 'package:notelore_core/src/store/format.dart';
import 'package:notelore_core/src/store/index.dart';
import 'package:notelore_core/src/store/notes.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../support/files.dart';

DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);
final today = d(2026, 9, 30);

/// Built once: every write is a flush to disk, which is slow on Windows.
String buildTree(String root) {
  final mopsos = createNote(root, 'project', 'Mopsos', tags: ['investing'], today: today);
  recordDecision(mopsos, 'database', 'PostgreSQL', today: d(2026, 9, 12));
  recordDecision(mopsos, 'frontend', 'React + Vite', today: d(2026, 9, 20));
  recordDecision(
    mopsos,
    'database',
    'SQLite',
    reason: 'Single user, zero setup.',
    today: d(2026, 9, 28),
  );
  addEntry(mopsos, 'Considered adding crypto, postponed.', today: d(2026, 9, 22));
  addTodo(mopsos, 'Add Drive backup', due: d(2026, 10, 15), today: today);
  File(mopsos)
      .writeAsStringSync('\n## Links\nhand-written zettelkasten link\n', mode: FileMode.append);
  final sirket = createNote(root, 'topic', 'Şirket Kuruluşu', lang: 'tr', today: d(2026, 8, 1));
  addEntry(sirket, 'Muhasebeci ile görüşüldü, ücret 2.500 TL.', today: d(2026, 8, 5));
  recordDecision(sirket, 'Şirket-Türü', 'Limited', today: d(2026, 8, 5));
  File(p.join(root, 'topics', 'not-a-note.md')).writeAsStringSync('just some markdown\n');
  File(p.join(root, 'topics', 'latin1.md'))
      .writeAsBytesSync('---\ntitle: caf\xe9\n---\n# x\n'.codeUnits);
  File(p.join(root, 'topics', 'odd-date.md')).writeAsStringSync(
    '---\ntitle: Odd\nkind: topic\ncreated: 2026-01-01\nupdated: soon\n---\n# Odd\n',
  );
  createNote(p.join(root, '_archive', '2026-01-01'), 'project', 'Old', today: today);
  return root;
}

void main() {
  late String tree;
  setUpAll(() => tree = buildTree(p.join(tempDir(), 'notes')));

  late String root;
  late String db;
  setUp(() {
    final dir = tempDir();
    root = p.join(dir, 'notes');
    db = p.join(dir, 'state', 'index.sqlite');
    copyTree(tree, root);
  });

  test('the bundled SQLite has FTS5 and the probe reports it', () {
    final memory = sqlite3.openInMemory();
    addTearDown(memory.close);
    expect(fts5Available(memory), isTrue);
    expect(fts5Available(_NoFts5()), isFalse);
  });

  test('the backend follows the probe by default', () {
    final index = NoteIndex(db, root);
    addTearDown(index.close);
    expect(index.fts, isTrue);
  });

  for (final fts in [true, false]) {
    group(fts ? 'fts5' : 'like', () {
      late NoteIndex idx;
      setUp(() {
        idx = NoteIndex(db, root, fts5: fts)..rebuild();
        addTearDown(() => idx.close());
        expect(idx.fts, fts);
      });

      List<String> slugs() => [for (final n in idx.listNotes()) n.slug];

      test('listNotes skips the archive and non-notes', () {
        expect(idx.listNotes(), [
          NoteInfo('mopsos', 'project', 'Mopsos', today),
          NoteInfo('sirket-kurulusu', 'topic', 'Şirket Kuruluşu', d(2026, 8, 5)),
          const NoteInfo('odd-date', 'topic', 'Odd', null),
        ]);
        expect(idx.listNotes(kind: 'topic').map((n) => n.slug), ['sirket-kurulusu', 'odd-date']);
      });

      test('getDecision is the newest active one', () {
        expect(
          idx.getDecision('mopsos', 'database'),
          Decision(d(2026, 9, 28), 'database', 'SQLite. Single user, zero setup.'),
        );
        expect(idx.getDecision('mopsos', 'hosting'), isNull);
        expect(idx.getDecision('nope', 'database'), isNull);
      });

      test('lookups normalize the topic like the writer does', () {
        final nfd = unorm.nfd(' Şirket-Türü ');
        final decision = idx.getDecision('sirket-kurulusu', nfd);
        expect(decision, Decision(d(2026, 8, 5), 'şirket-türü', 'Limited.'));
        expect(idx.decisionHistory('sirket-kurulusu', topic: nfd), [decision]);
      });

      test('the same slug in both kinds needs the kind', () {
        for (final (kind, value) in [('project', 'Postgres'), ('topic', 'Redis')]) {
          recordDecision(
            createNote(root, kind, 'Dup', today: today),
            'database',
            value,
            today: today,
          );
        }
        idx.rebuild();
        final ambiguous = throwsA(
          isA<StateError>().having((e) => e.message, 'message', contains('project and topic')),
        );
        expect(() => idx.getDecision('dup', 'database'), ambiguous);
        expect(() => idx.decisionHistory('dup'), ambiguous);
        expect(
          idx.getDecision('dup', 'database', kind: 'topic'),
          Decision(today, 'database', 'Redis.'),
        );
        expect(idx.decisionHistory('dup', kind: 'project').map((d) => d.text), ['Postgres.']);
        expect(idx.getDecision('mopsos', 'database', kind: 'topic'), isNull);
      });

      test('decisionHistory includes superseded ones in date order', () {
        expect(idx.decisionHistory('mopsos', topic: 'database'), [
          Decision(d(2026, 9, 12), 'database', 'PostgreSQL.', superseded: d(2026, 9, 28)),
          Decision(d(2026, 9, 28), 'database', 'SQLite. Single user, zero setup.'),
        ]);
        expect(idx.decisionHistory('mopsos').map((d) => d.topic), [
          'database',
          'frontend',
          'database',
        ]);
      });

      test('search finds entries, decisions, todos and hand-written lines', () {
        final hits = idx.search('crypto');
        expect(hits.map((h) => (h.slug, h.section)), [('mopsos', 'notes')]);
        expect(hits.single.text, 'Considered adding crypto, postponed.');
        expect(hits.single.kind, 'project');
        expect(hits.single.title, 'Mopsos');
        expect(idx.search('sqlite').map((h) => h.section), ['decisions']);
        expect(idx.search('drive backup').map((h) => h.section), ['todo']);
        expect(idx.search('zettelkasten').map((h) => h.section), ['Links']);
        expect(idx.search('crypto', kind: 'topic'), isEmpty);
        expect(idx.search('nothing-like-this'), isEmpty);
      });

      test('any word is enough, and the line matching the most words comes first', () {
        expect(idx.search('backup drive').map((h) => h.section), ['todo']);
        // A question's other words ("which", "nothing") do not hide the hit.
        expect(idx.search('drive nothing').map((h) => h.section), ['todo']);
        final hits = idx.search('postponed crypto sqlite');
        expect(hits.first.text, 'Considered adding crypto, postponed.'); // two of three words
        expect(hits.map((h) => h.section), containsAll(['notes', 'decisions']));
      });

      test('a Turkish question finds a note in another inflection (#92)', () {
        final path = createNote(
          root,
          'project',
          'Deniz Kitabı Satın Alma',
          lang: 'tr',
          today: today,
        );
        addTodo(path, 'Deniz kitabını satın al', today: today);
        idx.rebuild();
        // "kitap", "kitabı", "kitabını": one stem; the question words match nothing.
        for (final query in ['hangi kitabı alacaktım', 'kitap', 'Kitabını']) {
          expect(
            idx.search(query).map((h) => h.slug),
            contains('deniz-kitabi-satin-alma'),
            reason: query,
          );
        }
        expect(idx.search('ve bu'), isEmpty); // words under three letters are not searched
      });

      test('search marks superseded decisions', () {
        expect(idx.search('postgresql').single.superseded, isTrue);
        expect(idx.search('zero setup').single.superseded, isFalse);
        expect(idx.search('crypto').single.superseded, isFalse);
      });

      test('search is case and accent insensitive for Turkish', () {
        for (final query in ['MUHASEBECİ', 'görüşüldü', 'gorusuldu']) {
          expect(idx.search(query).map((h) => h.slug), ['sirket-kurulusu'], reason: query);
        }
      });

      test('search tolerates query syntax', () {
        expect(
          idx.search('crypto "quoted" -x AND OR NOT ('),
          idx.search('crypto quoted x and or not'),
        );
        expect(idx.search(r'%_\'), isEmpty);
        expect(idx.search('   '), isEmpty);
      });

      test('rebuild is incremental', () {
        final mopsos = p.join(root, 'projects', 'mopsos.md');
        final file = File(mopsos);
        final stamp = file.lastModifiedSync();
        // Same size and mtime: not even read, so the old text stays indexed.
        file.writeAsStringSync(read(mopsos).replaceAll('crypto', 'cryptx'));
        file.setLastModifiedSync(stamp);
        idx.rebuild();
        expect(idx.search('crypto'), hasLength(1));
        // A new mtime with the old content: read, hashed, not reparsed.
        file.writeAsStringSync(read(mopsos).replaceAll('cryptx', 'crypto'));
        file.setLastModifiedSync(stamp.add(const Duration(seconds: 1)));
        idx.rebuild();
        expect(idx.search('crypto'), hasLength(1));
        addEntry(mopsos, 'Now with kubernetes.', today: d(2026, 10, 1));
        idx.rebuild();
        expect(idx.search('kubernetes').map((h) => h.slug), ['mopsos']);
        expect(idx.listNotes().first.updated, d(2026, 10, 1));
        archiveNote(root, mopsos, today: d(2026, 10, 1));
        idx.rebuild();
        expect(slugs(), ['sirket-kurulusu', 'odd-date']);
        expect(idx.getDecision('mopsos', 'database'), isNull);
        expect(idx.search('kubernetes'), isEmpty);
      });

      test('the index is derived state', () {
        List<Object> snapshot() => [
          idx.listNotes(),
          idx.decisionHistory('mopsos'),
          idx.search('crypto'),
        ];
        final before = snapshot();
        idx.close();
        final reopened = NoteIndex(db, root, fts5: fts);
        expect(reopened.listNotes(), before[0]); // same backend: the tables survive a reopen
        reopened.close();
        File(db).deleteSync();
        idx = NoteIndex(db, root, fts5: fts)..rebuild();
        expect(snapshot(), before);
      });

      test('unreadable files are skipped, not fatal', () {
        expect(slugs(), isNot(contains('latin1')));
        File(p.join(root, 'projects', 'mopsos.md')).writeAsBytesSync([0xFF, 0xFE, 0x20, 0x78]);
        idx.rebuild();
        expect(slugs(), isNot(contains('mopsos')));
        expect(idx.search('crypto'), isEmpty);
      });

      test('a file that stops being a note is forgotten', () {
        File(p.join(root, 'projects', 'mopsos.md')).writeAsStringSync('# broken now\n');
        idx.rebuild();
        expect(slugs(), ['sirket-kurulusu', 'odd-date']);
        expect(idx.search('crypto'), isEmpty);
      });

      test('the same mtime with a new size is reindexed', () {
        final file = File(p.join(root, 'projects', 'mopsos.md'));
        final stamp = file.lastModifiedSync();
        file.writeAsStringSync('${file.readAsStringSync()}\n## Links\nkubernetes\n');
        file.setLastModifiedSync(stamp); // rewritten within the filesystem's mtime granularity
        idx.rebuild();
        expect(idx.search('kubernetes').map((h) => h.slug), ['mopsos']);
      });

      test('a missing notes folder is an empty index', () {
        final empty = NoteIndex(p.join(tempDir(), 'i.sqlite'), p.join(root, 'nope'), fts5: fts)
          ..rebuild();
        addTearDown(empty.close);
        expect(empty.listNotes(), isEmpty);
      });
    });
  }

  test('reopening without FTS5 rebuilds the derived tables', () {
    final first = NoteIndex(db, root, fts5: true)..rebuild();
    final expected = [first.listNotes(), first.search('crypto')];
    first.close();
    final second = NoteIndex(db, root, fts5: false);
    addTearDown(second.close);
    expect(second.fts, isFalse);
    expect(second.listNotes(), isEmpty);
    second.rebuild();
    expect([second.listNotes(), second.search('crypto')], expected);
  });

  test('a failed rebuild rolls back and leaves the database usable', () {
    final index = NoteIndex(db, root, fts5: false);
    addTearDown(index.close);
    final other = sqlite3.open(db);
    addTearDown(other.close);
    other.execute('DROP TABLE content');
    expect(index.rebuild, throwsA(isA<SqliteException>()));
    other.execute(
      'CREATE TABLE content(slug, title, section, text, kind, path, superseded, folded)',
    );
    index.rebuild(); // no transaction left open
    expect(index.listNotes(), hasLength(3));
  });

  test('a failed setup closes the connection', () {
    File(db)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('x' * 4096);
    expect(() => NoteIndex(db, root), throwsA(isA<SqliteException>()));
    File(db).deleteSync(); // Windows refuses this while a handle is open
  });

  test('values compare by value', () {
    expect(
      const NoteInfo('a', 'topic', 'A', null).hashCode,
      const NoteInfo('a', 'topic', 'A', null).hashCode,
    );
    expect(const NoteInfo('a', 'topic', 'A', null), isNot(const NoteInfo('b', 'topic', 'A', null)));
    const hit = Hit('a', 'topic', 'A', 'notes', 'x', superseded: false);
    expect(hit.hashCode, const Hit('a', 'topic', 'A', 'notes', 'x', superseded: false).hashCode);
    expect(hit, isNot(const Hit('a', 'topic', 'A', 'notes', 'x', superseded: true)));
    expect('$hit', contains('notes'));
    expect('${const NoteInfo('a', 'topic', 'A', null)}', contains('a'));
  });
}

class _NoFts5 implements Database {
  @override
  void execute(String sql, [List<Object?> parameters = const []]) =>
      throw SqliteException(extendedResultCode: 1, message: 'no such module: fts5');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
