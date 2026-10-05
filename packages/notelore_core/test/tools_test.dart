import 'dart:convert';
import 'dart:io';

import 'package:notelore_core/src/store/index.dart';
import 'package:notelore_core/src/tools.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/files.dart';

final today = DateTime.utc(2026, 9, 30);

/// A toolbox over a fresh notes folder, closed after the test.
Toolbox newBox() {
  final dir = tempDir();
  final root = p.join(dir, 'notes');
  final box = Toolbox(root, NoteIndex(p.join(dir, 'state', 'index.sqlite'), root), today: today);
  addTearDown(box.index.close);
  return box;
}

void main() {
  schemaTests();
  late Toolbox box;
  setUp(() => box = newBox());

  Object? call(String name, [Map<String, Object?> args = const {}]) {
    final text = box.call(name, args);
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }

  test('schemas are well formed', () {
    expect(box.tools.map((t) => t.name), [
      'list_notes',
      'read_note',
      'create_note',
      'add_note_entry',
      'add_todo',
      'complete_todo',
      'record_decision',
      'get_decision',
      'decision_history',
      'search_notes',
      'find_stale_notes',
      'archive',
    ]);
    for (final tool in box.tools) {
      expect(tool.description, isNotEmpty);
      expect(tool.inputSchema['type'], 'object');
      final properties = tool.inputSchema['properties']! as Map;
      for (final required in tool.inputSchema['required']! as List) {
        expect(properties, contains(required), reason: tool.name);
      }
    }
  });

  test('create, list, read', () {
    expect(
      call('create_note', {
        'kind': 'project',
        'title': 'Mopsos',
        'tags': ['investing'],
      }),
      {'slug': 'mopsos', 'kind': 'project', 'path': 'projects/mopsos.md'},
    );
    expect(
      (call('create_note', {'kind': 'topic', 'title': 'Şirket', 'lang': 'tr'})! as Map)['slug'],
      'sirket',
    );
    expect(call('list_notes'), [
      {'slug': 'mopsos', 'kind': 'project', 'title': 'Mopsos', 'updated': '2026-09-30'},
      {'slug': 'sirket', 'kind': 'topic', 'title': 'Şirket', 'updated': '2026-09-30'},
    ]);
    expect((call('list_notes', {'kind': 'topic'})! as List).map((n) => (n as Map)['slug']), [
      'sirket',
    ]);
    final text = call('read_note', {'slug': 'sirket'})! as String;
    expect(text, startsWith('---\ntitle: Şirket\n'));
    expect(text, contains('## Kararlar'));
  });

  test('entries, todos and decisions', () {
    call('create_note', {'kind': 'project', 'title': 'Mopsos'});
    expect(call('add_note_entry', {'slug': 'mopsos', 'text': 'Weekly hit rate.'}), 'ok');
    expect(call('add_todo', {'slug': 'mopsos', 'text': 'Set up CI'}), 'ok');
    expect(call('add_todo', {'slug': 'mopsos', 'text': 'Backup', 'due': '2026-10-15'}), 'ok');
    expect(call('complete_todo', {'slug': 'mopsos', 'number': 1}), 'ok');
    expect(
      call('record_decision', {'slug': 'mopsos', 'topic': 'database', 'value': 'PostgreSQL'}),
      'ok',
    );
    expect(
      call('record_decision', {
        'slug': 'mopsos',
        'topic': 'database',
        'value': 'SQLite',
        'reason': 'Zero setup.',
      }),
      'ok',
    );
    expect(call('get_decision', {'slug': 'mopsos', 'topic': 'database'}), {
      'date': '2026-09-30',
      'topic': 'database',
      'value': 'SQLite',
      'reason': 'Zero setup.',
      'superseded': null,
    });
    expect(
      call('get_decision', {'slug': 'mopsos', 'topic': 'hosting'}),
      "No active decision for 'hosting' in 'mopsos'.",
    );
    final history = call('decision_history', {'slug': 'mopsos'})! as List;
    expect(history.map((d) => ((d as Map)['value'], d['superseded'])), [
      ('PostgreSQL', '2026-09-30'),
      ('SQLite', null),
    ]);
    expect(call('decision_history', {'slug': 'mopsos', 'topic': 'nope'}), isEmpty);
    final text = call('read_note', {'slug': 'mopsos'})! as String;
    expect(text, contains('- [x] 2026-09-30: Set up CI\n- [ ] 2026-10-15: Backup\n'));
    expect(text, contains('~~2026-09-30 — **database**: PostgreSQL.~~'));
  });

  test('search and stale', () {
    call('create_note', {'kind': 'project', 'title': 'Mopsos'});
    call('add_note_entry', {'slug': 'mopsos', 'text': 'Considered adding crypto.'});
    call('add_todo', {'slug': 'mopsos', 'text': 'Old', 'due': '2026-01-01'});
    expect(call('search_notes', {'query': 'crypto'}), [
      {
        'slug': 'mopsos',
        'kind': 'project',
        'title': 'Mopsos',
        'section': 'notes',
        'text': 'Considered adding crypto.',
        'superseded': false,
      },
    ]);
    expect(call('search_notes', {'query': 'crypto', 'kind': 'topic'}), isEmpty);
    expect(call('find_stale_notes'), [
      {
        'slug': 'mopsos',
        'kind': 'project',
        'reason': 'overdue todo',
        'section': 'todo',
        'number': 1,
        'date': '2026-01-01',
      },
    ]);
  });

  test('archive entries and the whole file', () {
    call('create_note', {'kind': 'project', 'title': 'Mopsos'});
    call('add_note_entry', {'slug': 'mopsos', 'text': 'keep'});
    call('add_note_entry', {'slug': 'mopsos', 'text': 'old'});
    expect(
      call('archive', {
        'slug': 'mopsos',
        'entries': {
          'notes': [2],
        },
      }),
      {'archived_to': '_archive/2026-09-30/projects/mopsos.md'},
    );
    expect(call('read_note', {'slug': 'mopsos'}), isNot(contains('old')));
    expect(call('archive', {'slug': 'mopsos'}), {
      'archived_to': '_archive/2026-09-30/projects/mopsos-2.md',
    });
    expect(call('list_notes'), isEmpty);
    expect(
      File(p.join(box.root, '_archive', '2026-09-30', 'projects', 'mopsos-2.md')).existsSync(),
      isTrue,
    );
  });

  test('a file the store cannot read is an error message', () {
    call('create_note', {'kind': 'project', 'title': 'Mopsos'});
    File(p.join(box.root, 'projects', 'mopsos.md')).writeAsBytesSync([0xFF, 0xFE, 0x20]);
    expect(call('add_note_entry', {'slug': 'mopsos', 'text': 'x'}), startsWith('Error: '));
  });

  test('errors come back as messages, not exceptions', () {
    expect(call('read_note', {'slug': 'nope'}), "Error: no note with slug 'nope'.");
    final outside = File(p.join(p.dirname(box.root), 'secret.md'))..writeAsStringSync('private\n');
    for (final (tool, extra) in [
      ('read_note', <String, Object?>{}),
      ('add_note_entry', {'text': 'x'}),
      ('archive', <String, Object?>{}),
    ]) {
      expect(
        call(tool, {'slug': '../../secret', ...extra}),
        startsWith('Error: invalid slug'),
        reason: tool,
      );
    }
    expect(outside.readAsStringSync(), 'private\n');
    expect(
      call('create_note', {'kind': 'diary', 'title': 'x'}),
      startsWith('Error: unknown note kind'),
    );
    call('create_note', {'kind': 'project', 'title': 'Dup'});
    call('create_note', {'kind': 'topic', 'title': 'Dup'});
    expect(
      call('read_note', {'slug': 'dup'}),
      "Error: 'dup' exists as both project and topic; pass kind.",
    );
    expect(
      call('read_note', {'slug': 'dup', 'kind': 'topic'}),
      startsWith('---\ntitle: Dup\nkind: topic'),
    );
    expect(
      call('create_note', {'kind': 'project', 'title': 'Dup'}),
      startsWith('Error: note already exists'),
    );
    expect(
      call('complete_todo', {'slug': 'dup', 'number': 3, 'kind': 'topic'}),
      startsWith('Error: '),
    );
    expect(
      call('add_todo', {'slug': 'dup', 'text': 'x', 'due': 'not-a-date', 'kind': 'topic'}),
      "Error: due must be a date as YYYY-MM-DD, got 'not-a-date'.",
    );
    expect(
      call('archive', {
        'slug': 'dup',
        'kind': 'topic',
        'entries': {
          'links': [1],
        },
      }),
      startsWith('Error: no known section'),
    );
    expect(
      call('record_decision', {'slug': 'dup', 'kind': 'topic', 'topic': 'a*b', 'value': 'x'}),
      startsWith('Error: decision topic'),
    );
    expect(
      call('get_decision', {'slug': 'dup', 'topic': 'db'}),
      startsWith("Error: 'dup' exists as"),
    );
    expect(call('nonsense'), "Error: unknown tool 'nonsense'.");
    expect(call('read_note'), "Error: read_note is missing the argument 'slug'.");
    expect(
      call('read_note', {'slug': 'x', 'colour': 'red'}),
      "Error: read_note got an unknown argument 'colour'.",
    );
    expect(
      call('complete_todo', {'slug': 'dup', 'number': 'two', 'kind': 'topic'}),
      "Error: complete_todo expects 'number' to be integer, got string.",
    );
    expect(
      call('create_note', {'kind': 'topic', 'title': 'T', 'tags': 'not-a-list'}),
      "Error: create_note expects 'tags' to be array, got string.",
    );
    expect(
      call('complete_todo', {'slug': 'dup', 'number': true, 'kind': 'topic'}),
      "Error: complete_todo expects 'number' to be integer, got boolean.",
    );
    expect(
      call('complete_todo', {'slug': 'dup', 'number': 1.5, 'kind': 'topic'}),
      "Error: complete_todo expects 'number' to be integer, got number.",
    );
    expect(
      call('add_todo', {'slug': 'dup', 'text': 'null due is fine', 'due': null, 'kind': 'topic'}),
      'ok',
    );
    expect(
      call('create_note', {
        'kind': 'topic',
        'title': 'T',
        'tags': ['ok', 2],
      }),
      "Error: create_note expects every item of 'tags' to be string, got integer.",
    );
    expect(
      call('archive', {
        'slug': 'dup',
        'kind': 'topic',
        'entries': {
          'notes': ['one'],
        },
      }),
      "Error: archive expects every item of 'entries.notes' to be integer, got string.",
    );
    expect(
      call('archive', {
        'slug': 'dup',
        'kind': 'topic',
        'entries': {'notes': 1},
      }),
      "Error: archive expects 'entries.notes' to be array, got integer.",
    );
    expect(
      call('archive', {'slug': 'dup', 'kind': 'topic', 'entries': <Object?>[]}),
      "Error: archive expects 'entries' to be object, got array.",
    );
  });

  test('the date defaults to today', () {
    final dir = tempDir();
    final root = p.join(dir, 'notes');
    final plain = Toolbox(root, NoteIndex(p.join(dir, 'i.sqlite'), root));
    addTearDown(plain.index.close);
    expect(plain.call('create_note', {'kind': 'topic', 'title': 'T'}), contains('topics/t.md'));
    expect(plain.call('find_stale_notes', {}), '[]');
  });
}

void schemaTests() {
  test('the tool list cannot be changed by a caller', () {
    expect(() => noteTools.add(noteTools.first), throwsUnsupportedError);
  });
}
