import 'dart:async';
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

      void refresh(String path) {
        idx.markChanged(path);
        idx.rebuild();
      }

      test('listNotes skips the archive and non-notes', () {
        expect(idx.listNotes(), [
          NoteInfo('mopsos', 'project', 'Mopsos', today),
          NoteInfo('sirket-kurulusu', 'topic', 'Şirket Kuruluşu', d(2026, 8, 5)),
          const NoteInfo('odd-date', 'topic', 'Odd', null),
        ]);
        expect(idx.listNotes(kind: 'topic').map((n) => n.slug), ['sirket-kurulusu', 'odd-date']);
      });

      test('related notes (#229): a shared title word, or several matching lines', () {
        final mopsos = idx.related('Mopsos backend').single;
        expect((mopsos.slug, mopsos.kind, mopsos.title), ('mopsos', 'project', 'Mopsos'));
        expect(mopsos.titleWords, ['mopsos']);
        expect(mopsos.lines, 0);
        // Across categories and languages: a topic for a project's question.
        final sirket = idx.related('Şirket vergisi', about: 'muhasebeci');
        expect(sirket.single.slug, 'sirket-kurulusu');
        expect(sirket.single.titleWords, ['sirket']);
        expect(sirket.single.lines, greaterThan(0));
        // No title word in common, but what it is about is already written down.
        final crypto = idx.related('Crypto', about: 'crypto postponed, maybe SQLite');
        expect(crypto.single.slug, 'mopsos');
        expect(crypto.single.titleWords, isEmpty);
        expect(crypto.single.lines, greaterThanOrEqualTo(2));
        // One loose line is not enough; common words do not count.
        expect(idx.related('Gardening', about: 'zettelkasten'), isEmpty);
        expect(idx.related('The notes for my project'), isEmpty);
        expect(idx.related('Odd Mopsos').map((r) => r.slug), ['mopsos', 'odd-date']);
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
          final path = createNote(root, kind, 'Dup', today: today);
          recordDecision(path, 'database', value, today: today);
          idx.markChanged(path);
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

      test('a question that names a note searches only that note (#219)', () {
        final notelore = createNote(root, 'project', 'Notelore', today: today);
        addEntry(notelore, 'Sync goes through Google Drive.', today: today);
        final work = createNote(root, 'project', 'Work Notes', today: today);
        addEntry(work, 'Meeting notes go to Confluence.', today: today);
        final school = createNote(root, 'topic', 'Okul', lang: 'tr', today: today);
        addEntry(school, 'Notlar Pazartesi paylaşılacak.', today: today);
        for (final path in [notelore, work, school]) {
          idx.markChanged(path);
        }
        idx.rebuild();
        // "notelore" shares the prefix "note" with "notes" and "Notlar".
        for (final query in ['Notelore', "Notelore'daki notlar", 'my notes about notelore']) {
          expect(idx.search(query).map((h) => h.slug).toSet(), {'notelore'}, reason: query);
        }
        // Every word of a title must be there: "notes" alone names no note.
        for (final query in ['notes', 'meeting notes']) {
          expect(idx.search(query).map((h) => h.slug), containsAll(['notelore', 'work-notes']));
        }
        expect(idx.search('work notes').map((h) => h.slug).toSet(), {'work-notes'});
        // Whole words only: a note titled "Plan" does not capture "planning".
        final plan = createNote(root, 'topic', 'Plan', today: today);
        addEntry(plan, 'Draft the roadmap.', today: today);
        refresh(plan);
        expect(idx.search('planning work notes').map((h) => h.slug).toSet(), {'work-notes'});
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
        refresh(path);
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

      test('a long inflection finds a note that only has the bare root', () {
        final path = createNote(root, 'topic', 'Okuma', lang: 'tr', today: today);
        addEntry(path, 'Yeni bir kitap aldım.', today: today);
        refresh(path);
        for (final query in ['kitabını', 'kitabımızı']) {
          expect(idx.search(query).map((h) => h.slug), contains('okuma'), reason: query);
        }
      });

      test('the closer match still ranks first', () {
        // "postgresql" also reaches "postponed" through its short prefix, but lower.
        expect(idx.search('postgresql').first.section, 'decisions');
      });

      test('search marks superseded decisions', () {
        expect(idx.search('postgresql').first.superseded, isTrue); // the decision ranks first
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
        refresh(mopsos);
        expect(idx.search('crypto'), hasLength(1));
        addEntry(mopsos, 'Now with kubernetes.', today: d(2026, 10, 1));
        refresh(mopsos);
        expect(idx.search('kubernetes').map((h) => h.slug), ['mopsos']);
        expect(idx.listNotes().first.updated, d(2026, 10, 1));
        archiveNote(root, mopsos, today: d(2026, 10, 1));
        refresh(mopsos);
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
        final path = p.join(root, 'projects', 'mopsos.md');
        File(path).writeAsBytesSync([0xFF, 0xFE, 0x20, 0x78]);
        refresh(path);
        expect(slugs(), isNot(contains('mopsos')));
        expect(idx.search('crypto'), isEmpty);
      });

      test('a file that stops being a note is forgotten', () {
        final path = p.join(root, 'projects', 'mopsos.md');
        File(path).writeAsStringSync('# broken now\n');
        refresh(path);
        expect(slugs(), ['sirket-kurulusu', 'odd-date']);
        expect(idx.search('crypto'), isEmpty);
      });

      test('the same mtime with a new size is reindexed', () {
        final file = File(p.join(root, 'projects', 'mopsos.md'));
        final stamp = file.lastModifiedSync();
        file.writeAsStringSync('${file.readAsStringSync()}\n## Links\nkubernetes\n');
        file.setLastModifiedSync(stamp); // rewritten within the filesystem's mtime granularity
        refresh(file.path);
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

  test('a failed changed-file refresh rolls back and can be retried', () {
    final index = NoteIndex(db, root, fts5: false)..rebuild();
    addTearDown(index.close);
    final other = sqlite3.open(db);
    addTearDown(other.close);
    other.execute(
      'CREATE TRIGGER fail_refresh BEFORE INSERT ON content '
      "BEGIN SELECT RAISE(ABORT, 'blocked'); END",
    );
    final path = p.join(root, 'projects', 'mopsos.md');
    addEntry(path, 'Retry this refresh.', today: today);
    index.markChanged(path);
    expect(index.rebuild, throwsA(isA<SqliteException>()));
    expect(index.search('crypto'), hasLength(1)); // the old index survived rollback
    other.execute('DROP TRIGGER fail_refresh');
    index.rebuild();
    expect(index.search('retry').map((hit) => hit.slug), ['mopsos']);
  });

  test('a failed setup closes the connection', () {
    File(db)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('x' * 4096);
    expect(() => NoteIndex(db, root), throwsA(isA<SqliteException>()));
    File(db).deleteSync(); // Windows refuses this while a handle is open
  });

  test('an unchanged refresh does not stat every note again', () {
    var noteStats = 0;
    final watches = <String, StreamController<FileSystemEvent>>{};
    addTearDown(() async {
      for (final watch in watches.values) {
        await watch.close();
      }
    });
    IOOverrides.runZoned(
      () {
        final index = NoteIndex(db, root);
        addTearDown(index.close);
        index.rebuild();
        noteStats = 0;
        index.rebuild();
        expect(noteStats, 0);
        final changed = File(p.join(root, 'projects', 'mopsos.md'));
        addEntry(changed.path, 'Incremental refresh marker.', today: today);
        watches[p.join(root, 'projects')]!.add(FileSystemModifyEvent(changed.path, false, true));
        noteStats = 0;
        index.rebuild();
        expect(noteStats, 1);
        expect(index.search('incremental').map((hit) => hit.slug), ['mopsos']);
        final stamp = changed.lastModifiedSync();
        changed.writeAsStringSync(changed.readAsStringSync().replaceAll('marker', 'foobar'));
        changed.setLastModifiedSync(stamp);
        watches[p.join(root, 'projects')]!.add(FileSystemModifyEvent(changed.path, false, true));
        index.rebuild();
        expect(index.search('foobar').map((hit) => hit.slug), ['mopsos']);
        changed.deleteSync();
        watches[p.join(root, 'projects')]!.add(FileSystemDeleteEvent(changed.path, false));
        index.rebuild();
        expect(index.listNotes().map((note) => note.slug), isNot(contains('mopsos')));
        final oldPath = p.join(root, 'topics', 'odd-date.md');
        final newPath = p.join(root, 'topics', 'renamed.md');
        File(oldPath).renameSync(newPath);
        watches[p.join(root, 'topics')]!.add(FileSystemMoveEvent(oldPath, false, newPath));
        index.rebuild();
        expect(index.listNotes().map((note) => note.slug), contains('renamed'));
        expect(index.listNotes().map((note) => note.slug), isNot(contains('odd-date')));
        watches[p.join(root, 'projects')]!.addError(const FileSystemException('watch overflow'));
        noteStats = 0;
        index.rebuild();
        expect(noteStats, greaterThan(1)); // a failed watcher falls back to the full scan
      },
      statSync: (path) {
        if (path.endsWith('.md')) noteStats++;
        return Zone.root.run(() => FileStat.statSync(path));
      },
      fsWatch: (path, _, _) => watches
          .putIfAbsent(path, () => StreamController<FileSystemEvent>.broadcast(sync: true))
          .stream,
    );
  });

  test('a known write is indexed before the watcher delivers its event', () {
    final index = NoteIndex(db, root)..rebuild();
    addTearDown(index.close);
    final changed = p.join(root, 'projects', 'mopsos.md');
    addEntry(changed, 'Immediate refresh marker.', today: today);
    index.markChanged(changed);
    index.rebuild();
    expect(index.search('immediate').map((hit) => hit.slug), ['mopsos']);
  });

  test('an explicit full scan finds a change whose event was missed', () {
    final index = NoteIndex(db, root)..rebuild();
    addTearDown(index.close);
    final path = p.join(root, 'projects', 'mopsos.md');
    addEntry(path, 'Missed notification marker.', today: today);
    index.invalidateAll();
    index.rebuild();
    expect(index.search('notification').map((hit) => hit.slug), ['mopsos']);
  });

  test('a marked write is read during a full audit even with the old stamp', () {
    final index = NoteIndex(db, root)..rebuild();
    addTearDown(index.close);
    final path = p.join(root, 'projects', 'mopsos.md');
    final file = File(path);
    final stamp = file.lastModifiedSync();
    file.writeAsStringSync(file.readAsStringSync().replaceAll('crypto', 'krypta'));
    file.setLastModifiedSync(stamp);
    index
      ..markChanged(path)
      ..invalidateAll()
      ..rebuild();
    expect(index.search('krypta').map((hit) => hit.slug), ['mopsos']);
  });

  test('a new kind folder is watched and indexed', () {
    final dir = tempDir();
    final notes = p.join(dir, 'notes');
    createNote(notes, 'project', 'First', today: today);
    final watches = <String, StreamController<FileSystemEvent>>{};
    addTearDown(() async {
      for (final watch in watches.values) {
        await watch.close();
      }
    });
    IOOverrides.runZoned(
      () {
        final index = NoteIndex(p.join(dir, 'index.sqlite'), notes)..rebuild();
        addTearDown(index.close);
        expect(watches.containsKey(p.join(notes, 'topics')), isFalse);
        final second = createNote(notes, 'topic', 'Second', today: today);
        watches[notes]!.add(FileSystemCreateEvent(p.dirname(second), true));
        index.rebuild();
        expect(index.listNotes().map((note) => note.slug), contains('second'));
        expect(watches.containsKey(p.join(notes, 'topics')), isTrue);
      },
      fsWatch: (path, _, _) => watches
          .putIfAbsent(path, () => StreamController<FileSystemEvent>.broadcast(sync: true))
          .stream,
    );
  });

  test('an unavailable file watcher falls back to scanning', () {
    IOOverrides.runZoned(() {
      final index = NoteIndex(db, root);
      addTearDown(index.close);
      index.rebuild();
      final path = p.join(root, 'projects', 'mopsos.md');
      addEntry(path, 'Watcher fallback marker.', today: today);
      index.rebuild();
      expect(index.search('fallback').map((hit) => hit.slug), ['mopsos']);
    }, fsWatch: (_, _, _) => throw UnsupportedError('watch unavailable'));
  });

  test('a watcher that cannot start falls back to scanning', () {
    IOOverrides.runZoned(() {
      final index = NoteIndex(db, root);
      addTearDown(index.close);
      index.rebuild();
      final path = p.join(root, 'projects', 'mopsos.md');
      addEntry(path, 'Start failure marker.', today: today);
      index.rebuild();
      expect(index.search('failure').map((hit) => hit.slug), ['mopsos']);
    }, fsWatch: (_, _, _) => throw const FileSystemException('cannot watch'));
  });

  test('a watcher that closes falls back to scanning', () async {
    final watches = <String, StreamController<FileSystemEvent>>{};
    addTearDown(() async {
      for (final watch in watches.values) {
        await watch.close();
      }
    });
    await IOOverrides.runZoned(
      () async {
        final index = NoteIndex(db, root)..rebuild();
        addTearDown(index.close);
        await watches[p.join(root, 'projects')]!.close();
        final path = p.join(root, 'projects', 'mopsos.md');
        addEntry(path, 'Closed watcher marker.', today: today);
        index.rebuild();
        expect(index.search('closed').map((hit) => hit.slug), ['mopsos']);
      },
      fsWatch: (path, _, _) => watches
          .putIfAbsent(path, () => StreamController<FileSystemEvent>.broadcast(sync: true))
          .stream,
    );
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
