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
      // the same file archived again the same day: nothing is overwritten
      createNote(root, 'project', 'Mopsos', today: today);
      expect(archiveNote(root, path, today: today), p.join(p.dirname(target), 'mopsos-2.md'));
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
      expect(target, p.join(root, '_archive', '2026-09-30', 'projects', 'mopsos.md'));
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
}
