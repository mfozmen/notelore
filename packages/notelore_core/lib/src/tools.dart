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
/// - `record_decision(slug, topic, value, reason?, kind?)`: supersedes the active
///   decision for `topic` in the same write.
/// - `get_decision(slug, topic, kind?)`: the current decision, deterministic.
/// - `decision_history(slug, topic?, kind?)`: every decision incl. superseded.
/// - `search_notes(query, kind?)`: full-text hits.
/// - `find_stale_notes()`: cleanup candidates with 1-based entry numbers.
/// - `archive(slug, entries?, kind?)`: moves numbered entries per section, or the
///   whole file when `entries` is omitted, under `_archive/`.
///
/// `kind` (`project` | `topic`) is only needed when the same slug exists as
/// both. No tool overwrites a file or deletes anything. Ported from the Python
/// reference.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

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

final noteTools = [
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
    'Full-text search over every note; every word must match, in any order.',
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
];

final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

class Toolbox {
  Toolbox(this.root, this.index, {this.today});

  final String root;
  final NoteIndex index;

  /// Tests pin it; the app uses the local date.
  final DateTime? today;

  List<Tool> get tools => noteTools;

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
      'add_note_entry' => _ok(
        () => notes.addEntry(_path(arg('slug'), kind), arg('text'), today: today),
      ),
      'add_todo' => _ok(
        () => notes.addTodo(
          _path(arg('slug'), kind),
          arg('text'),
          due: _due(optional('due')),
          today: today,
        ),
      ),
      'complete_todo' => _ok(
        () => notes.completeTodo(_path(arg('slug'), kind), args['number']! as int, today: today),
      ),
      'record_decision' => _ok(
        () => notes.recordDecision(
          _path(arg('slug'), kind),
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
      _ => _archive(arg('slug'), args['entries'] as Map?, kind), // 'archive'
    };
  }

  // ------------------------------------------------------------ helpers

  String _path(String slug, String? kind) {
    bool exists(String k) => File(notes.notePath(root, k, slug)).existsSync();
    final found = kind != null ? [kind] : notes.kinds.keys.where(exists).toList();
    if (found.length > 1) throw StateError("'$slug' exists as both project and topic; pass kind.");
    if (found.isEmpty || !exists(found.single)) {
      throw FileSystemException("no note with slug '$slug'.");
    }
    return notes.notePath(root, found.single, slug);
  }

  String _rel(String path) => p.split(p.relative(path, from: root)).join('/');

  NoteIndex _fresh() => index..rebuild();

  static String _ok(void Function() write) {
    write();
    return 'ok';
  }

  static DateTime? _due(String? due) {
    if (due == null) return null;
    final date = _isoDate.hasMatch(due) ? parseIsoDate(due) : null;
    return date ?? (throw FormatException("due must be a date as YYYY-MM-DD, got '$due'."));
  }

  // ------------------------------------------------------------ tools

  Map<String, Object?> _createNote(String kind, String title, List<String>? tags, String lang) {
    final path = notes.createNote(root, kind, title, tags: tags, lang: lang, today: today);
    return {'slug': p.basenameWithoutExtension(path), 'kind': kind, 'path': _rel(path)};
  }

  Object _getDecision(String slug, String topic, String? kind) {
    _path(slug, kind); // the same "pass kind" message as every other tool
    final decision = _fresh().getDecision(slug, topic, kind: kind);
    return decision == null ? "No active decision for '$topic' in '$slug'." : _decision(decision);
  }

  List<Map<String, Object?>> _decisionHistory(String slug, String? topic, String? kind) {
    _path(slug, kind);
    return [for (final d in _fresh().decisionHistory(slug, topic: topic, kind: kind)) _decision(d)];
  }

  Map<String, Object?> _archive(String slug, Map<Object?, Object?>? entries, String? kind) {
    final path = _path(slug, kind);
    final target = entries == null || entries.isEmpty
        ? notes.archiveNote(root, path, today: today)
        : notes.archiveEntries(root, path, {
            for (final MapEntry(:key, :value) in entries.entries)
              '$key': (value! as List).cast<int>(),
          }, today: today);
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
    if (!args.containsKey(required)) return "${tool.name} is missing the argument '$required'.";
  }
  for (final MapEntry(:key, :value) in args.entries) {
    final schema = properties[key];
    if (schema == null) return "${tool.name} got an unknown argument '$key'.";
    if (_checkValue(tool.name, key, value, schema as Map<String, Object?>) case final problem?) {
      return problem;
    }
  }
  return null;
}

/// Type checks one value, descending into array items and object values.
String? _checkValue(String tool, String key, Object? value, Map<String, Object?> schema) {
  final expected = schema['type']! as String;
  if (value == null) return null;
  if (!_is(value, expected)) {
    return "$tool expects '$key' to be $expected, got ${_jsonType(value)}.";
  }
  if (value is List) {
    final itemType = (schema['items']! as Map)['type']! as String;
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
