import 'dart:convert';
import 'dart:io';

import 'package:notelore_core/src/store/format.dart';
import 'package:notelore_core/src/store/notes.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../support/files.dart';

DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);
final today = d(2026, 9, 30);

List<NoteEntry> entries(String path, String key) => readNote(path).section(key)?.entries ?? [];

FileSystemException held() =>
    const FileSystemException('held by antivirus', 'x', OSError('Access is denied', 5));

void main() {
  late String root;
  setUp(() => root = p.join(tempDir(), 'notes'));

  group('slugify', () {
    final cases = {
      'Mopsos': 'mopsos',
      'Şirket Kuruluşu': 'sirket-kurulusu',
      "İstanbul'a Taşınma: Plan": 'istanbula-tasinma-plan',
      'Çığ / Öğle <Üşüme>': 'cig-ogle-usume',
      '  --Hello   World--  ': 'hello-world',
      'Café résumé': 'cafe-resume',
      'Typographic ’quote': 'typographic-quote',
      'CON': 'con-note',
      'aux.txt': 'aux-txt',
      'lpt9': 'lpt9-note',
      '!!!': 'untitled',
      'a' * 150: 'a' * 100,
      'word ' * 40: ('word-' * 20).substring(0, 99),
    };
    for (final MapEntry(key: title, value: slug) in cases.entries) {
      test(jsonEncode(title), () {
        expect(slugify(title), slug);
        expect(slugify(slug), slug); // idempotent
      });
    }
  });

  group('notePath', () {
    test('per kind', () {
      expect(notePath(root, 'project', 'mopsos'), p.join(root, 'projects', 'mopsos.md'));
      expect(notePath(root, 'topic', 'x'), p.join(root, 'topics', 'x.md'));
      expect(
        () => notePath(root, 'diary', 'x'),
        throwsA(isA<ArgumentError>().having((e) => '$e', 'message', contains('kind'))),
      );
    });

    for (final slug in [
      '../../etc/passwd',
      '..',
      '.',
      'x/y',
      r'x\y',
      'a:b',
      '',
      'a\nb',
      'a\rb',
      'a\x00b',
    ]) {
      test('rejects ${jsonEncode(slug)}', () {
        expect(
          () => notePath(root, 'project', slug),
          throwsA(isA<ArgumentError>().having((e) => '$e', 'message', contains('slug'))),
        );
      });
    }

    test('accepts hand-made file names', () {
      expect(notePath(root, 'topic', 'My Note'), p.join(root, 'topics', 'My Note.md'));
    });
  });

  group('atomicWrite', () {
    test('is UTF-8, LF and leaves no temp file', () {
      final path = p.join(root, 'a', 'n.md');
      atomicWrite(path, '# Şükrü\nline\n');
      expect(File(path).readAsBytesSync(), utf8.encode('# Şükrü\nline\n'));
      expect(Directory(p.dirname(path)).listSync().map((e) => p.basename(e.path)), ['n.md']);
    });

    test('replaces an existing file', () {
      final path = p.join(root, 'n.md');
      atomicWrite(path, 'old');
      atomicWrite(path, 'new');
      expect(read(path), 'new');
    });

    test('retries while Windows holds the file', () {
      final path = p.join(root, 'n.md');
      atomicWrite(path, 'old');
      final naps = <Duration>[];
      var failures = 0;
      atomicWrite(
        path,
        'new',
        rename: (source, target) {
          if (failures++ < 2) throw held();
          File(source).renameSync(target);
        },
        pause: naps.add,
      );
      expect(read(path), 'new');
      expect(naps, [const Duration(milliseconds: 50), const Duration(milliseconds: 100)]);
    });

    test('gives up after the retries and cleans up the temp file', () {
      final path = p.join(root, 'n.md');
      var attempts = 0;
      expect(
        () => atomicWrite(
          path,
          'x',
          rename: (_, _) {
            attempts++;
            throw held();
          },
          pause: (_) {},
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(attempts, 5);
      expect(File(path).existsSync(), isFalse);
      expect(Directory(root).listSync(), isEmpty);
    });

    test('does not retry an error that is not a held file', () {
      var attempts = 0;
      expect(
        () => moveWithRetry(
          'a',
          'b',
          rename: (_, _) {
            attempts++;
            throw const FileSystemException('gone', 'a', OSError('not found', 2));
          },
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(attempts, 1);
    });

    test('moveWithRetry waits for a file Obsidian holds', () {
      final source = p.join(root, 'a.md');
      final target = p.join(root, 'sub', 'a.md');
      atomicWrite(source, 'x');
      Directory(p.dirname(target)).createSync();
      var failed = false;
      moveWithRetry(
        source,
        target,
        rename: (from, to) {
          if (!failed) {
            failed = true;
            throw held();
          }
          File(from).renameSync(to);
        },
        pause: (_) {},
      );
      expect(read(target), 'x');
      expect(File(source).existsSync(), isFalse);
    });
  });

  group('create, read, write', () {
    test('createNote writes the canonical file', () {
      final path = createNote(root, 'project', 'Mopsos', tags: ['investing'], today: today);
      expect(path, p.join(root, 'projects', 'mopsos.md'));
      expect(
        read(path),
        '---\ntitle: Mopsos\nkind: project\ncreated: 2026-09-30\nupdated: 2026-09-30\n'
        'tags: [investing]\n---\n# Mopsos\n\n## Decisions\n\n## Notes\n\n## Todo\n',
      );
    });

    test('createNote in Turkish', () {
      final text = read(createNote(root, 'topic', 'Şirket', lang: 'tr', today: today));
      expect(text, isNot(contains('tags')));
      expect(text, endsWith('# Şirket\n\n## Kararlar\n\n## Notlar\n\n## Yapılacaklar\n'));
    });

    test('createNote refuses to overwrite', () {
      createNote(root, 'project', 'Mopsos', today: today);
      expect(
        () => createNote(root, 'project', 'MOPSOS', today: today), // same slug
        throwsA(isA<FileSystemException>()),
      );
    });

    test('writeNote maintains updated', () {
      final path = createNote(root, 'project', 'Mopsos', today: today);
      writeNote(path, readNote(path), today: d(2026, 10, 2));
      expect(readNote(path).meta['updated'], d(2026, 10, 2));
      expect(readNote(path).meta['created'], today);
    });

    test('today defaults to the local calendar date', () {
      final now = DateTime.now();
      expect(localToday(), DateTime.utc(now.year, now.month, now.day));
      final path = createNote(root, 'project', 'Mopsos');
      expect(readNote(path).meta['created'], localToday());
      addEntry(path, 'e');
      addTodo(path, 't');
      addReminder(path, 'r', d(2026, 11, 1));
      recordDecision(path, 'db', 'x');
      final note = readNote(path);
      expect(note.section('notes')!.entries.first, Entry(localToday(), 'e'));
      expect(note.section('todo')!.entries.first, Todo(localToday(), 't'));
      expect(note.section('decisions')!.entries.first, Decision(localToday(), 'db', 'x.'));
    });
  });

  group('entries', () {
    test('addEntry appends before the trailing blank line', () {
      final path = createNote(root, 'project', 'Mopsos', today: today);
      addEntry(path, 'Weekly hit rate.', today: today);
      addEntry(path, 'Second\nline with\r\nCRLF', today: d(2026, 10, 1));
      final text = read(path);
      expect(
        text,
        contains(
          '## Notes\n- 2026-09-30: Weekly hit rate.\n- 2026-10-01: Second\n  line with\n  CRLF\n'
          '\n## Todo\n',
        ),
      );
      expect(text, contains('updated: 2026-10-01'));
      expect(entries(path, 'notes')[1], Entry(d(2026, 10, 1), 'Second\n  line with\n  CRLF'));
    });

    final missing = {
      'no-sections': ('# Bare\n', '# Bare\n## Notes\n- 2026-09-30: Merhaba\n'),
      'turkish': ('# Bare\n\n## Kararlar\n', '## Kararlar\n\n## Notlar\n- 2026-09-30: Merhaba\n'),
      'already-blank': (
        '# Bare\n\n## Kararlar\n\n',
        '## Kararlar\n\n## Notlar\n- 2026-09-30: Merhaba\n',
      ),
    };
    for (final MapEntry(key: name, value: (tail, expected)) in missing.entries) {
      test('addEntry creates a missing section in the file language: $name', () {
        final path = p.join(root, 'topics', 'bare.md');
        const front =
            '---\ntitle: Bare\nkind: topic\ncreated: 2026-09-01\nupdated: 2026-09-01\n---\n';
        atomicWrite(path, front + tail);
        addEntry(path, 'Merhaba', today: today);
        expect(read(path), endsWith(expected));
      });
    }

    test('todos', () {
      final path = createNote(root, 'project', 'Mopsos', today: today);
      addTodo(path, 'Set up CI', today: today);
      addTodo(path, 'Add Drive backup', due: d(2026, 10, 15), today: today);
      completeTodo(path, 1, today: today);
      expect(
        read(path),
        contains('## Todo\n- [x] 2026-09-30: Set up CI\n- [ ] 2026-10-15: Add Drive backup\n'),
      );
      expect(() => completeTodo(path, 3, today: today), throwsA(isA<RangeError>()));
      expect(() => completeTodo(path, 0, today: today), throwsA(isA<RangeError>()));
    });

    test('reminders get their own section at the end, once (#430)', () {
      final path = createNote(root, 'project', 'Mopsos', today: today);
      addReminder(path, 'Renew the domain', d(2026, 11, 1), time: '09:00', today: today);
      addReminder(path, '  Pay the hosting  ', d(2026, 11, 2), today: today);
      expect(
        read(path),
        endsWith(
          '## Todo\n\n## Reminders\n'
          '- 2026-11-01 09:00: Renew the domain\n- 2026-11-02: Pay the hosting\n',
        ),
      );
      final turkish = createNote(root, 'topic', 'Diş', lang: 'tr', today: today);
      addReminder(turkish, 'Dişçi randevusu', d(2026, 10, 20), time: '10:00', today: today);
      expect(read(turkish), endsWith('## Hatırlatıcılar\n- 2026-10-20 10:00: Dişçi randevusu\n'));
      for (final time in ['9:00', '24:00', '10:60', 'noon']) {
        expect(
          () => addReminder(path, 'x', d(2026, 11, 3), time: time, today: today),
          throwsA(isA<ArgumentError>()),
          reason: time,
        );
      }
    });

    test('identical todos are completed by position', () {
      final path = createNote(root, 'project', 'Mopsos', today: today);
      addTodo(path, 'same', today: today);
      addTodo(path, 'same', today: today);
      completeTodo(path, 2, today: today);
      expect(entries(path, 'todo').take(2), [Todo(today, 'same'), Todo(today, 'same', done: true)]);
    });

    test('written text is NFC', () {
      final nfd = unorm.nfd('Şükrü');
      final path = createNote(root, 'topic', nfd, today: today);
      addEntry(path, nfd, today: today);
      recordDecision(path, nfd, nfd, reason: nfd, today: today);
      final text = read(path);
      expect(unorm.nfc(text), text);
      // title, heading, entry, topic, value and reason
      expect('Şükrü'.allMatches(text).length + 'şükrü'.allMatches(text).length, 6);
    });

    test('an NFD topic supersedes the NFC one', () {
      final path = createNote(root, 'project', 'Mopsos', today: today);
      recordDecision(path, 'şirket', 'A', today: d(2026, 9, 1));
      recordDecision(path, unorm.nfd('şirket'), 'B', today: today);
      final decisions = entries(path, 'decisions').whereType<Decision>();
      expect(decisions.map((e) => e.superseded), [today, null]);
      expect(activeDecision(readNote(path), unorm.nfd('şirket')), isNotNull);
    });

    test('decision value and topic are normalized', () {
      final path = createNote(root, 'project', 'Mopsos', today: today);
      recordDecision(path, ' Database ', 'SQLite\r\nsingle file.', today: today);
      expect(entries(path, 'decisions')[0], Decision(today, 'database', 'SQLite\n  single file.'));
      for (final topic in ['a*b', 'a\nb', '  ']) {
        expect(
          () => recordDecision(path, topic, 'x', today: today),
          throwsA(isA<ArgumentError>().having((e) => '$e', 'message', contains('topic'))),
        );
      }
    });

    test('recordDecision supersedes the active one for the topic', () {
      final path = createNote(root, 'project', 'Mopsos', today: today);
      recordDecision(path, 'database', 'PostgreSQL', today: d(2026, 9, 12));
      recordDecision(path, 'frontend', 'React + Vite.', today: d(2026, 9, 20));
      recordDecision(
        path,
        'database',
        'SQLite',
        reason: 'Single user, zero setup.',
        today: d(2026, 9, 28),
      );
      final decisions = entries(path, 'decisions').whereType<Decision>().toList();
      expect(decisions, [
        Decision(d(2026, 9, 12), 'database', 'PostgreSQL.', superseded: d(2026, 9, 28)),
        Decision(d(2026, 9, 20), 'frontend', 'React + Vite.'),
        Decision(d(2026, 9, 28), 'database', 'SQLite. Single user, zero setup.'),
      ]);
      final note = readNote(path);
      expect(activeDecision(note, 'database'), decisions[2]);
      expect(activeDecision(note, 'hosting'), isNull);
    });

    test('activeDecision of a note without decisions is null', () {
      final note = parse('---\ntitle: T\n---\n# T\n');
      expect(activeDecision(note, 'database'), isNull);
    });

    test('an empty reason adds nothing', () {
      final path = createNote(root, 'project', 'Mopsos', today: today);
      recordDecision(path, 'db', 'SQLite', reason: '', today: today);
      expect(entries(path, 'decisions')[0], Decision(today, 'db', 'SQLite.'));
    });
  });

  test('note files are readable by other tools', () {
    final path = createNote(root, 'project', 'Mopsos', today: today);
    if (!Platform.isWindows) {
      final umask = Process.runSync('sh', ['-c', 'umask']).stdout.toString().trim();
      expect(File(path).statSync().mode & 0x1FF, 0x1B6 & ~int.parse(umask, radix: 8));
    }
  });

  group('archive', () {
    test('archiveNote moves the file keeping its relative path', () {
      final path = createNote(root, 'project', 'Mopsos', today: today);
      final target = archiveNote(root, path, today: today);
      expect(target, p.join(root, '_archive', '2026-09-30', 'projects', 'mopsos.md'));
      expect(File(path).existsSync(), isFalse);
      expect(read(target), startsWith('---\ntitle: Mopsos'));
      // the same file archived again the same day: a numbered day, the same name
      createNote(root, 'project', 'Mopsos', today: today);
      expect(
        archiveNote(root, path, today: today),
        p.join(root, '_archive', '2026-09-30-2', 'projects', 'mopsos.md'),
      );
      createNote(root, 'project', 'Mopsos', today: today);
      expect(
        archiveNote(root, path, today: today),
        p.join(root, '_archive', '2026-09-30-3', 'projects', 'mopsos.md'),
      );
      createNote(root, 'project', 'Mopsos', today: today);
      expect(archiveNote(root, path), endsWith('mopsos.md'));
    });

    test('archiveEntries moves them to the archive copy', () {
      final path = createNote(root, 'project', 'Mopsos', today: today);
      addEntry(path, 'keep', today: today);
      addEntry(path, 'old one', today: today);
      addTodo(path, 'done', today: today);
      completeTodo(path, 1, today: today);
      final target = archiveEntries(root, path, {
        'notes': [2],
        'todo': [1],
      }, today: today);
      expect(target, p.join(root, '_archive', '2026-09-30', 'entries', 'projects', 'mopsos.md'));
      expect(entries(path, 'notes').whereType<Entry>(), [Entry(today, 'keep')]);
      expect(entries(path, 'todo').whereType<Todo>(), isEmpty);
      expect(readNote(target).title, 'Mopsos');
      expect(entries(target, 'notes')[0], Entry(today, 'old one'));
      expect(entries(target, 'todo'), contains(Todo(today, 'done', done: true)));
      // a second batch the same day appends to the same archive file
      addEntry(path, 'another old', today: today);
      expect(
        archiveEntries(root, path, {
          'notes': [2],
        }, today: today),
        target,
      );
      expect(entries(target, 'notes'), contains(Entry(today, 'another old')));
    });

    test('archiveEntries keeps the note language and defaults today', () {
      final path = createNote(root, 'topic', 'Şirket', lang: 'tr', today: today);
      addEntry(path, 'eski', today: today);
      final target = archiveEntries(root, path, {
        'notes': [1],
      });
      expect(read(target), contains('## Notlar\n'));
    });

    test('archiveEntries rejects bad numbers', () {
      final path = createNote(root, 'project', 'Mopsos', today: today);
      expect(
        () => archiveEntries(root, path, {
          'notes': [1],
        }, today: today),
        throwsA(isA<RangeError>()),
      );
      expect(
        () => archiveEntries(root, path, {
          'links': [1],
        }, today: today),
        throwsA(isA<ArgumentError>().having((e) => '$e', 'message', contains('section'))),
      );
      addEntry(path, 'one', today: today);
      expect(
        () => archiveEntries(root, path, {
          'notes': [1, 1],
        }, today: today),
        throwsA(isA<ArgumentError>().having((e) => '$e', 'message', contains('twice'))),
      );
    });

    test('an unknown section with a matching heading is not archivable', () {
      final path = createNote(root, 'project', 'Mopsos', today: today);
      File(path).writeAsStringSync('${read(path)}## Links\n- x\n');
      expect(
        () => archiveEntries(root, path, {
          'Links': [1],
        }, today: today),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('raw lines are never archived as entries', () {
      final path = createNote(root, 'project', 'Mopsos', today: today);
      final note = readNote(path);
      note.section('notes')!.entries.insert(0, const Raw('hand written'));
      writeNote(path, note, today: today);
      expect(
        () => archiveEntries(root, path, {
          'notes': [1],
        }, today: today),
        throwsA(isA<RangeError>()),
      );
    });
  });

  group('the archive, browsed and restored', () {
    late String root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('notelore_archive_').path;
      addTearDown(() => Directory(root).deleteSync(recursive: true));
    });

    test('lists what was archived, newest first, and restores it to its place', () {
      final older = createNote(root, 'topic', 'Kitaplar', today: DateTime(2026, 10, 1));
      archiveNote(root, older, today: DateTime(2026, 10, 2));
      final newer = createNote(root, 'project', 'Mopsos', today: DateTime(2026, 10, 1));
      archiveNote(root, newer, today: DateTime(2026, 10, 5));
      File(p.join(root, archiveFolder, '2026-10-05', 'stray.txt')).writeAsStringSync('x');
      final listed = listArchived(root);
      expect(listed.map((a) => (a.title, a.archivedOn, a.original)), [
        ('Mopsos', '2026-10-05', 'projects/mopsos.md'),
        ('Kitaplar', '2026-10-02', 'topics/kitaplar.md'),
      ]);
      final restored = restoreArchived(root, listed.last);
      expect(restored, p.join(root, 'topics', 'kitaplar.md'));
      expect(readNote(restored).title, 'Kitaplar');
      expect(listArchived(root), hasLength(1));
    });

    test('never overwrites a note that took the name again', () {
      final first = createNote(root, 'topic', 'Kitaplar', today: DateTime(2026, 10, 1));
      archiveNote(root, first, today: DateTime(2026, 10, 2));
      createNote(root, 'topic', 'Kitaplar', today: DateTime(2026, 10, 3)); // a new one
      final archived = listArchived(root).single;
      expect(() => restoreArchived(root, archived), throwsA(isA<RestoreTaken>()));
      expect(File(archived.path).existsSync(), isTrue); // still in the archive
      expect('${RestoreTaken(archived.original)}', contains('topics/kitaplar.md'));
    });

    test('an empty archive, and an archived file that is not a note', () {
      expect(listArchived(root), isEmpty);
      File(p.join(root, archiveFolder, '2026-10-02', 'topics', 'broken.md'))
        ..createSync(recursive: true)
        ..writeAsStringSync('no front matter');
      expect(listArchived(root).single.title, 'broken'); // named after the file
    });

    test('a note archived twice the same day comes back under its own name', () {
      final path = createNote(root, 'topic', 'Kitaplar', today: DateTime(2026, 10, 1));
      archiveNote(root, path, today: DateTime(2026, 10, 2));
      createNote(root, 'topic', 'Kitaplar', today: DateTime(2026, 10, 2));
      archiveNote(root, path, today: DateTime(2026, 10, 2));
      final listed = listArchived(root);
      expect(listed.map((a) => (a.archivedOn, a.original)), [
        ('2026-10-02', 'topics/kitaplar.md'),
        ('2026-10-02', 'topics/kitaplar.md'),
      ]);
      expect(restoreArchived(root, listed.last), p.join(root, 'topics', 'kitaplar.md'));
    });

    test('a restore leaves no empty folder in the archive (#490)', () {
      final path = createNote(root, 'topic', 'Kitaplar', today: DateTime(2026, 10, 1));
      addEntry(path, 'Dune', today: DateTime(2026, 10, 1));
      archiveEntries(root, path, {
        'notes': [1],
      }, today: DateTime(2026, 10, 2));
      restoreArchived(root, listArchived(root).single);
      final other = createNote(root, 'project', 'Mopsos', today: DateTime(2026, 10, 1));
      archiveNote(root, other, today: DateTime(2026, 10, 3));
      restoreArchived(root, listArchived(root).single);
      expect(Directory(p.join(root, archiveFolder)).listSync(), isEmpty);
    });

    test('archived entries are listed as entries and go back into their note', () {
      final path = createNote(root, 'topic', 'Kitaplar', today: DateTime(2026, 10, 1));
      addEntry(path, 'Dune', today: DateTime(2026, 10, 1));
      addEntry(path, 'Solaris', today: DateTime(2026, 10, 1));
      archiveEntries(root, path, {
        'notes': [1],
      }, today: DateTime(2026, 10, 2));
      final archived = listArchived(root).single;
      expect(archived.entries, isTrue);
      expect(archived.original, 'topics/kitaplar.md');
      expect(archived.title, 'Kitaplar');

      expect(restoreArchived(root, archived), path); // merged back, the note kept
      expect(entries(path, 'notes').whereType<Entry>().map((e) => e.text), ['Solaris', 'Dune']);
      expect(listArchived(root), isEmpty);

      // The note gone meanwhile: the entries come back as the note.
      archiveEntries(root, path, {
        'notes': [1],
      }, today: DateTime(2026, 10, 3));
      archiveNote(root, path, today: DateTime(2026, 10, 3));
      final copy = listArchived(root).firstWhere((a) => a.entries);
      expect(restoreArchived(root, copy), path);
      expect(entries(path, 'notes').whereType<Entry>().map((e) => e.text), ['Solaris']);
    });
  });

  group('attachments (#279)', () {
    test('an original is kept by its date, under a safe name, never over another', () {
      final first = keepAttachment(root, 'Sesli Not 1.M4A', [1, 2, 3], today: d(2026, 10, 18));
      expect(first, 'attachments/2026-10-18/sesli-not-1.m4a');
      expect(File(p.join(root, 'attachments', '2026-10-18', 'sesli-not-1.m4a')).readAsBytesSync(), [
        1,
        2,
        3,
      ]);
      final second = keepAttachment(root, 'sesli not 1.m4a', [9], today: d(2026, 10, 18));
      expect(second, 'attachments/2026-10-18/sesli-not-1-2.m4a');
      expect(File(p.join(root, 'attachments', '2026-10-18', 'sesli-not-1.m4a')).lengthSync(), 3);
      expect(
        keepAttachment(root, '../../x', [0], today: d(2026, 10, 18)),
        'attachments/2026-10-18/x',
      );
      expect(
        keepAttachment(root, 'con.wav', [0], today: d(2026, 10, 18)),
        'attachments/2026-10-18/con-note.wav',
      );
    });
  });

  group('merge (#229)', () {
    late String from;
    late String into;

    setUp(() {
      into = createNote(root, 'project', 'Home Server', tags: ['home'], today: d(2026, 9, 1));
      addEntry(into, 'The server runs on a Raspberry Pi.', today: d(2026, 9, 2));
      recordDecision(into, 'backup', 'Restic', today: d(2026, 9, 3));
      addTodo(into, 'Buy a UPS', today: d(2026, 9, 4));
      from = createNote(
        root,
        'topic',
        'Raspberry Pi',
        tags: ['hardware', 'home'],
        today: d(2026, 9, 5),
      );
      addEntry(from, 'The server runs on a Raspberry Pi.', today: d(2026, 9, 2)); // the same entry
      addEntry(from, 'It needs a 27 W power supply.', today: d(2026, 9, 6));
      recordDecision(from, 'backup', 'Borg', reason: 'Deduplicates better.', today: d(2026, 9, 7));
      recordDecision(from, 'os', 'Debian', today: d(2026, 9, 8));
      addTodo(from, 'Order a case', today: d(2026, 9, 9));
    });

    test('keeps every entry once, the newest decision active, and archives the source', () {
      final result = mergeNotes(root, from, into, today: today);
      expect(result.added, 4);
      expect(result.duplicates, 1);
      expect(File(from).existsSync(), isFalse);
      expect(
        result.archivedTo,
        p.join(root, archiveFolder, '2026-09-30', 'topics', 'raspberry-pi.md'),
      );
      expect(File(result.archivedTo).existsSync(), isTrue); // nothing lost, only moved
      expect(entries(into, 'notes').where((e) => e is! Raw), [
        Entry(d(2026, 9, 2), 'The server runs on a Raspberry Pi.'),
        Entry(d(2026, 9, 6), 'It needs a 27 W power supply.'),
      ]);
      expect(entries(into, 'todo').whereType<Todo>().map((t) => t.text), [
        'Buy a UPS',
        'Order a case',
      ]);
      final decisions = entries(into, 'decisions').whereType<Decision>().toList();
      expect(decisions.map((d) => (d.topic, d.text, d.superseded)), [
        ('backup', 'Restic.', d(2026, 9, 7)), // the newer one from the source wins
        ('backup', 'Borg. Deduplicates better.', null),
        ('os', 'Debian.', null),
      ]);
      final note = readNote(into);
      expect(note.meta['tags'], ['home', 'hardware']);
      expect(note.meta['updated'], today);
      expect(note.meta['title'], 'Home Server');
    });

    test('loose lines, the preamble and unknown sections come along', () {
      File(from).writeAsStringSync(
        '---\ntitle: Raspberry Pi\nkind: topic\n---\n# Raspberry Pi\n\nA small computer.\n\n'
        '## Notes\n\n- 2026-09-06: It needs a 27 W power supply.\nA loose line.\n\n'
        '## Links\n\n- https://www.raspberrypi.com\n',
      );
      mergeNotes(root, from, into); // today by default
      final note = readNote(into);
      expect(note.preamble.where((l) => l.trim().isNotEmpty), ['A small computer.']);
      expect(entries(into, 'notes'), contains(const Raw('A loose line.')));
      expect(entries(into, 'Links'), contains(const Raw('- https://www.raspberrypi.com')));
      expect(note.meta.containsKey('tags'), isTrue); // the target's own tags stay
    });

    test('a todo done in one note and open in the other is kept once, done (#283)', () {
      addTodo(from, 'Buy a UPS', today: d(2026, 9, 4)); // the target's open one, done here
      completeTodo(from, 2, today: d(2026, 9, 10));
      mergeNotes(root, from, into, today: today);
      final todos = entries(into, 'todo').whereType<Todo>().where((t) => t.text == 'Buy a UPS');
      expect(todos, hasLength(1));
      expect(todos.single.done, isTrue);
    });

    test('a note never merges into itself; a missing note fails before anything moves', () {
      expect(() => mergeNotes(root, into, into, today: today), throwsArgumentError);
      expect(
        () => mergeNotes(root, p.join(root, 'topics', 'gone.md'), into, today: today),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(into).existsSync(), isTrue);
    });

    test('a target that cannot be written leaves the source where it was', () {
      final before = File(into).readAsStringSync();
      expect(
        () => mergeNotes(
          root,
          from,
          into,
          today: today,
          rename: (_, _) => throw const FileSystemException('disk full'),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(from).existsSync(), isTrue);
      expect(File(into).readAsStringSync(), before);
    });
  });
}
