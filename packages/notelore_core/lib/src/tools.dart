/// The narrow tools the agent may call. Thin wrappers over the store.
///
/// Contracts (every result is a JSON string, or `"ok"`, or `"Error: ..."`; the
/// model never sees an exception):
///
/// - `list_notes(kind?)`: `[{slug, kind, title, updated}]`, newest first.
/// - `read_note(slug, kind?)`: the whole note as Markdown text.
/// - `create_note(kind, title, tags?, lang?)`: `{slug, kind, path}`; fails if it exists.
/// - `add_note_entry(slug, text, kind?)`: appends a dated entry under Notes.
/// - `add_todo(slug, text, due?, kind?)` / `complete_todo(slug, number, kind?)`.
/// - `add_reminder(slug, at, text, kind?)`: `at` is `YYYY-MM-DD` or `YYYY-MM-DD HH:MM`;
///   appended under Reminders, which the app turns into notifications.
/// - `record_decision(slug, topic, value, reason?, kind?)`: supersedes the active
///   decision for `topic` in the same write.
/// - `get_decision(slug, topic, kind?)`: the current decision, deterministic.
/// - `decision_history(slug, topic?, kind?)`: every decision incl. superseded.
/// - `search_notes(query, kind?)`: full-text hits, best first; any word may match;
///   a query that names a note (every word of its title) searches only that note.
/// - `find_stale_notes()`: cleanup candidates with 1-based entry numbers.
/// - `archive(slug, entries?, kind?)`: moves numbered entries per section, or the
///   whole file when `entries` is omitted, under `_archive/`.
/// - `related_notes(title, about?)`: notes in either category a new note may belong
///   with: `[{slug, kind, title, shares_title_words, matching_lines}]`, best first.
/// - `merge_notes(from, into, from_kind?, into_kind?)`: appends what `into` lacks of
///   `from`, then moves `from` under `_archive/`:
///   `{merged_into, archived_to, added, already_there}`.
///
/// `kind` (`project` | `topic`) is only needed when the same slug exists as
/// both. No tool overwrites a file or deletes anything. Ported from the Python
/// reference.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'providers/base.dart';
import 'store/format.dart';
import 'store/index.dart';
import 'store/notes.dart' as notes;
import 'store/stale.dart';

final _kind = {'type': 'string', 'enum': notes.kinds.keys.toList()};
const _slug = {'type': 'string', 'description': 'Note slug as listed by list_notes'};
const _date = {'type': 'string', 'description': 'YYYY-MM-DD'};
const _string = {'type': 'string'};

Map<String, Object?> _schema(List<String> required, [Map<String, Object?> properties = const {}]) =>
    {'type': 'object', 'properties': properties, 'required': required};

final noteTools = List<Tool>.unmodifiable([
  Tool(
    'list_notes',
    'Projects and topics with title, slug and last update.',
    _schema([], {'kind': _kind}),
  ),
  Tool(
    'read_note',
    'The full note as Markdown.',
    _schema(['slug'], {'slug': _slug, 'kind': _kind}),
  ),
  Tool(
    'create_note',
    'Create a new project or topic file. Fails if the title already maps to a file.',
    _schema(
      ['kind', 'title'],
      {
        'kind': _kind,
        'title': _string,
        'tags': {'type': 'array', 'items': _string, 'description': 'lowercase'},
        'lang': {
          'type': 'string',
          'enum': ['en', 'tr'],
          'description': 'language of the headings',
        },
      },
    ),
  ),
  Tool(
    'add_note_entry',
    "Append a dated note. Write one clean, self-contained sentence in the user's language.",
    _schema(['slug', 'text'], {'slug': _slug, 'text': _string, 'kind': _kind}),
  ),
  Tool(
    'add_todo',
    'Add an open todo; due is the due date if the user gave one.',
    _schema(['slug', 'text'], {'slug': _slug, 'text': _string, 'due': _date, 'kind': _kind}),
  ),
  Tool(
    'complete_todo',
    'Tick todo number N (1-based, as shown in read_note order).',
    _schema(
      ['slug', 'number'],
      {
        'slug': _slug,
        'number': {'type': 'integer'},
        'kind': _kind,
      },
    ),
  ),
  Tool(
    'add_reminder',
    'Add a reminder for a day, or a day and a time of day, in the note it belongs to. '
        'Only when the user asks to be reminded or names an appointment.',
    _schema(
      ['slug', 'at', 'text'],
      {
        'slug': _slug,
        'at': {'type': 'string', 'description': 'YYYY-MM-DD, or YYYY-MM-DD HH:MM (24-hour)'},
        'text': _string,
        'kind': _kind,
      },
    ),
  ),
  Tool(
    'record_decision',
    'Record a decision for a short lowercase topic key such as database or hosting. '
        'The previous active decision for that topic is marked superseded.',
    _schema(
      ['slug', 'topic', 'value'],
      {'slug': _slug, 'topic': _string, 'value': _string, 'reason': _string, 'kind': _kind},
    ),
  ),
  Tool(
    'get_decision',
    'The current decision for a topic. Always use this instead of reading free text.',
    _schema(['slug', 'topic'], {'slug': _slug, 'topic': _string, 'kind': _kind}),
  ),
  Tool(
    'decision_history',
    'All decisions of a note, including superseded ones, oldest first.',
    _schema(['slug'], {'slug': _slug, 'topic': _string, 'kind': _kind}),
  ),
  Tool(
    'search_notes',
    'Full-text search over every note: any word may match, best matches first; '
        'a query with every word of a note title searches only that note; '
        'word endings do not matter; words under three letters are ignored.',
    _schema(['query'], {'query': _string, 'kind': _kind}),
  ),
  Tool('find_stale_notes', 'Deterministic cleanup candidates.', _schema([])),
  Tool(
    'archive',
    'Move entries (by section and 1-based number) or the whole note to _archive/. '
        'Only after the user confirmed in the conversation.',
    _schema(
      ['slug'],
      {
        'slug': _slug,
        'entries': {
          'type': 'object',
          'description': '{"notes": [2, 5], "todo": [1]}; omit to archive the whole file',
          'additionalProperties': {
            'type': 'array',
            'items': {'type': 'integer'},
          },
        },
        'kind': _kind,
      },
    ),
  ),
  Tool(
    'related_notes',
    'Existing projects and topics a new note may belong with, by title words and content. '
        'Call before create_note.',
    _schema(
      ['title'],
      {
        'title': _string,
        'about': {'type': 'string', 'description': 'what the new note would say'},
      },
    ),
  ),
  Tool(
    'merge_notes',
    'Move everything of note "from" that "into" lacks into "into", then archive "from". '
        'Only after the user confirmed which note goes into which. A todo open in one '
        'and done in the other is the same todo: it is kept once, done.',
    _schema(
      ['from', 'into'],
      {'from': _slug, 'into': _slug, 'from_kind': _kind, 'into_kind': _kind},
    ),
  ),
]);

/// The tools a phone rarely needs, left out for the model on the device (#447).
const slimLeftOut = {'merge_notes', 'find_stale_notes', 'decision_history'};

/// Shorter words for the model on the device, where every token is read
/// before the first word comes.
const _slimDescriptions = {
  'create_note': 'Create a project or topic. Fails if it exists.',
  'add_note_entry': "Append a dated note: one self-contained sentence in the user's language.",
  'add_todo': 'Add an open todo; due if the user gave a date.',
  'complete_todo': 'Tick todo number N (1-based, in read_note order).',
  'add_reminder': 'Add a reminder for a day, or a day and a time, in the note it belongs to.',
  'record_decision':
      'Record a decision for a short lowercase topic key; the previous one is superseded.',
  'get_decision': 'The current decision for a topic.',
  'search_notes': 'Full-text search over every note, best matches first.',
  'archive': 'Move entries (by section and 1-based number) or the whole note to the archive.',
  'related_notes': 'Notes a new note may belong with. Call before create_note.',
};

/// [noteTools] for the model on the device (#447): fewer, in fewer words, with
/// the same arguments, so the toolbox checks a call as any other.
final slimTools = List<Tool>.unmodifiable([
  for (final tool in noteTools)
    if (!slimLeftOut.contains(tool.name))
      Tool(tool.name, _slimDescriptions[tool.name] ?? tool.description, _bare(tool.inputSchema)),
]);

/// [schema] without the slug's description, said again in nearly every tool;
/// the words that carry a format (a date, a time, entries) stay.
Map<String, Object?> _bare(Map<String, Object?> schema) => {
  ...schema,
  'properties': {
    for (final MapEntry(:key, :value) in (schema['properties']! as Map<String, Object?>).entries)
      key: identical(value, _slug) ? const {'type': 'string'} : value,
  },
};

final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

void _delete(File file) => file.deleteSync();

class Toolbox {
  Toolbox(this.root, this.index, {this.today, this.delete = _delete});

  final String root;
  final NoteIndex index;

  /// Tests pin it; the app uses the local date.
  final DateTime? today;

  List<Tool> get tools => noteTools;

  /// Removes a file; tests make it fail as a held file does on Windows.
  final void Function(File file) delete;

  /// This turn's new notes, as made: a failed turn takes back the empty ones (#421).
  final _created = <String, String>{};

  /// Whether this turn made a note; it stays.
  bool forgetCreated() {
    final any = _created.isNotEmpty;
    _created.clear();
    return any;
  }

  /// Undoes this turn's creates that nothing was written into, so nothing is
  /// lost (#421); whether a new note stays. Never throws: the turn's own error
  /// is what the caller must see.
  bool takeBackEmpty() {
    var kept = false;
    for (final MapEntry(key: path, value: made) in _created.entries) {
      final file = File(path);
      try {
        if (file.existsSync() && file.readAsStringSync() == made) {
          delete(file);
          index.markChanged(path);
          continue;
        }
      } on FileSystemException {
        // Held by another app: it stays, a note like any other.
      }
      kept = true;
    }
    _created.clear();
    return kept;
  }

  String call(String name, Map<String, Object?> args) {
    final tool = noteTools.where((t) => t.name == name).firstOrNull;
    if (tool == null) return "Error: unknown tool '$name'.";
    if (_checkArguments(tool, args) case final problem?) return 'Error: $problem';
    try {
      final result = _dispatch(name, args);
      return result is String ? result : jsonEncode(result);
    } on ArgumentError catch (error) {
      // Includes RangeError. Store validation failures, never a crash for the model.
      final value = error.invalidValue;
      return 'Error: ${error.message}${value == null ? '' : ' (got $value)'}';
    } on StateError catch (error) {
      return 'Error: ${error.message}';
    } on FormatException catch (error) {
      return 'Error: ${error.message}';
    } on FileSystemException catch (error) {
      // Includes a Windows "access denied" while another app holds the file.
      final cause = error.osError == null ? '' : ' (${error.osError!.message})';
      return 'Error: ${error.message}$cause';
    }
  }

  Object? _dispatch(String name, Map<String, Object?> args) {
    String arg(String key) => args[key]! as String;
    String? optional(String key) => args[key] as String?;
    final kind = optional('kind');
    return switch (name) {
      'list_notes' => [for (final n in _fresh().listNotes(kind: kind)) _noteInfo(n)],
      'read_note' => File(_path(arg('slug'), kind)).readAsStringSync(),
      'create_note' => _createNote(
        arg('kind'),
        arg('title'),
        (args['tags'] as List?)?.cast<String>(),
        optional('lang') ?? 'en',
      ),
      'add_note_entry' => _write(
        _path(arg('slug'), kind),
        (path) => notes.addEntry(path, arg('text'), today: today),
      ),
      'add_todo' => _write(
        _path(arg('slug'), kind),
        (path) => notes.addTodo(path, arg('text'), due: _due(optional('due')), today: today),
      ),
      'complete_todo' => _write(
        _path(arg('slug'), kind),
        (path) => notes.completeTodo(path, args['number']! as int, today: today),
      ),
      'add_reminder' => _write(_path(arg('slug'), kind), (path) {
        final (date, time) = _at(arg('at'));
        notes.addReminder(path, arg('text'), date, time: time, today: today);
      }),
      'record_decision' => _write(
        _path(arg('slug'), kind),
        (path) => notes.recordDecision(
          path,
          arg('topic'),
          arg('value'),
          reason: optional('reason'),
          today: today,
        ),
      ),
      'get_decision' => _getDecision(arg('slug'), arg('topic'), kind),
      'decision_history' => _decisionHistory(arg('slug'), optional('topic'), kind),
      'search_notes' => [for (final h in _fresh().search(arg('query'), kind: kind)) _hit(h)],
      'find_stale_notes' => [for (final s in findStaleNotes(root, today: today)) _stale(s)],
      'related_notes' => [
        for (final r in _fresh().related(arg('title'), about: optional('about'))) _related(r),
      ],
      'merge_notes' => _merge(
        _path(arg('from'), optional('from_kind')),
        _path(arg('into'), optional('into_kind')),
      ),
      _ => _archive(arg('slug'), args['entries'] as Map?, kind), // 'archive'
    };
  }

  // ------------------------------------------------------------ helpers

  /// The note [slug] names, as its file is named on disk: a slug in another
  /// case finds it on every OS (an exact name wins), and a write never takes
  /// the model's case (Windows would rename the file to it) (#367).
  String _path(String slug, String? kind) {
    String? onDisk(String k) {
      final exact = notes.notePath(root, k, slug); // checks the slug
      final folder = Directory(p.dirname(exact));
      if (!folder.existsSync()) return null;
      String key(String path) => unorm.nfc(p.basename(path)).toLowerCase();
      final files = [for (final f in folder.listSync().whereType<File>()) f.path];
      return files.where((f) => p.basename(f) == p.basename(exact)).firstOrNull ??
          files.where((f) => key(f) == key(exact)).firstOrNull;
    }

    final found = {
      for (final k in kind != null ? [kind] : notes.kinds.keys) k: onDisk(k),
    }..removeWhere((_, path) => path == null);
    if (found.length > 1) throw StateError("'$slug' exists as both project and topic; pass kind.");
    if (found.isEmpty) throw FileSystemException("no note with slug '$slug'.");
    return found.values.single!;
  }

  /// [slug] as its note's file is named (see [_path]).
  String _realSlug(String slug, String? kind) => p.basenameWithoutExtension(_path(slug, kind));

  String _rel(String path) => p.split(p.relative(path, from: root)).join('/');

  NoteIndex _fresh() => index..rebuild();

  String _write(String path, void Function(String) write) {
    write(path);
    index.markChanged(path);
    return 'ok';
  }

  /// A reminder's day and its time if it has one; the store checks the time.
  static (DateTime, String?) _at(String at) {
    final match = RegExp(r'^(\d{4}-\d{2}-\d{2})(?: (\d{1,2}:\d{2}))?$').firstMatch(at);
    final date = match == null ? null : parseIsoDate(match[1]!);
    if (date == null) {
      throw FormatException("at must be YYYY-MM-DD or YYYY-MM-DD HH:MM, got '$at'.");
    }
    return (date, match![2]);
  }

  static DateTime? _due(String? due) {
    if (due == null) return null;
    final date = _isoDate.hasMatch(due) ? parseIsoDate(due) : null;
    return date ?? (throw FormatException("due must be a date as YYYY-MM-DD, got '$due'."));
  }

  // ------------------------------------------------------------ tools

  Map<String, Object?> _createNote(String kind, String title, List<String>? tags, String lang) {
    final path = notes.createNote(root, kind, title, tags: tags, lang: lang, today: today);
    _created[path] = File(path).readAsStringSync();
    index.markChanged(path);
    return {'slug': p.basenameWithoutExtension(path), 'kind': kind, 'path': _rel(path)};
  }

  Object _getDecision(String slug, String topic, String? kind) {
    final real = _realSlug(slug, kind); // and the same "pass kind" message as every other tool
    final decision = _fresh().getDecision(real, topic, kind: kind);
    return decision == null ? "No active decision for '$topic' in '$slug'." : _decision(decision);
  }

  List<Map<String, Object?>> _decisionHistory(String slug, String? topic, String? kind) {
    final real = _realSlug(slug, kind);
    return [for (final d in _fresh().decisionHistory(real, topic: topic, kind: kind)) _decision(d)];
  }

  Map<String, Object?> _merge(String from, String into) {
    final (:archivedTo, :added, :duplicates) = notes.mergeNotes(root, from, into, today: today);
    index
      ..markChanged(from)
      ..markChanged(into);
    return {
      'merged_into': _rel(into),
      'archived_to': _rel(archivedTo),
      'added': added,
      'already_there': duplicates,
    };
  }

  Map<String, Object?> _archive(String slug, Map<Object?, Object?>? entries, String? kind) {
    final path = _path(slug, kind);
    final target = entries == null || entries.isEmpty
        ? notes.archiveNote(root, path, today: today)
        : notes.archiveEntries(root, path, {
            for (final MapEntry(:key, :value) in entries.entries)
              '$key': (value! as List).cast<int>(),
          }, today: today);
    index.markChanged(path);
    return {'archived_to': _rel(target)};
  }
}

String? _iso(DateTime? date) => date == null ? null : isoDate(date);

Map<String, Object?> _noteInfo(NoteInfo n) => {
  'slug': n.slug,
  'kind': n.kind,
  'title': n.title,
  'updated': _iso(n.updated),
};

Map<String, Object?> _hit(Hit h) => {
  'slug': h.slug,
  'kind': h.kind,
  'title': h.title,
  'section': h.section,
  'text': h.text,
  'superseded': h.superseded,
};

Map<String, Object?> _related(Related r) => {
  'slug': r.slug,
  'kind': r.kind,
  'title': r.title,
  'shares_title_words': r.titleWords,
  'matching_lines': r.lines,
};

Map<String, Object?> _stale(Stale s) => {
  'slug': s.slug,
  'kind': s.kind,
  'reason': s.reason,
  'section': s.section,
  'number': s.number,
  'date': isoDate(s.date),
};

Map<String, Object?> _decision(Decision d) => {
  'date': isoDate(d.date),
  'topic': d.topic,
  'value': d.value,
  'reason': d.reason,
  'superseded': _iso(d.superseded),
};

/// What is wrong with the model's arguments for [tool], or null.
///
/// Checked against the tool's own schema before dispatch, so a TypeError from
/// inside the store stays a real bug instead of turning into an Error message.
String? _checkArguments(Tool tool, Map<String, Object?> args) {
  final properties = tool.inputSchema['properties']! as Map<String, Object?>;
  for (final required in tool.inputSchema['required']! as List<String>) {
    if (!args.containsKey(required)) {
      return "${tool.name} is missing the argument '$required'. ${_callAs(tool)}";
    }
  }
  for (final MapEntry(:key, :value) in args.entries) {
    final schema = properties[key];
    if (schema == null) return "${tool.name} got an unknown argument '$key'. ${_callAs(tool)}";
    if (_checkValue(tool.name, key, value, schema as Map<String, Object?>) case final problem?) {
      return problem;
    }
  }
  return null;
}

/// How [tool] is called, every argument with its type ("?" when optional): a
/// small model fixes a wrong call in one step when the error shows it (#474).
String _callAs(Tool tool) {
  final required = tool.inputSchema['required']! as List<String>;
  String type(Map<String, Object?> schema) => switch (schema) {
    {'enum': final List<Object?> values} => values.map((v) => '"$v"').join(' | '),
    {'type': 'array', 'items': final Map<String, Object?> items} => '[${type(items)}]',
    _ => '${schema['type']}',
  };
  final arguments = [
    for (final MapEntry(:key, :value) in (tool.inputSchema['properties']! as Map).entries)
      '"$key"${required.contains(key) ? '' : '?'}: ${type((value as Map).cast())}',
  ];
  return 'Call it as ${tool.name}({${arguments.join(', ')}}).';
}

/// Type checks one value, descending into array items and object values.
String? _checkValue(String tool, String key, Object? value, Map<String, Object?> schema) {
  final expected = schema['type']! as String;
  if (value == null) return null;
  if (!_is(value, expected)) {
    return "$tool expects '$key' to be $expected, got ${_jsonType(value)}.";
  }
  if ((value, schema['items']) case (final List<Object?> value, final Map<String, Object?> items)) {
    final itemType = items['type']! as String;
    for (final item in value) {
      if (!_is(item, itemType)) {
        return "$tool expects every item of '$key' to be $itemType, got ${_jsonType(item)}.";
      }
    }
  }
  if ((value, schema['additionalProperties']) case (
    final Map<Object?, Object?> value,
    final Map<String, Object?> nested,
  )) {
    for (final MapEntry(key: name, value: item) in value.entries) {
      if (_checkValue(tool, '$key.$name', item, nested) case final problem?) return problem;
    }
  }
  return null;
}

bool _is(Object? value, String jsonType) => _jsonType(value) == jsonType;

String _jsonType(Object? value) => switch (value) {
  String() => 'string',
  int() => 'integer',
  double() => 'number',
  bool() => 'boolean',
  List() => 'array',
  Map() => 'object',
  _ => 'null',
};
