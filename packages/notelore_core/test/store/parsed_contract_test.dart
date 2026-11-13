import 'dart:convert';
import 'dart:io';

import 'package:notelore_core/src/store/format.dart';
import 'package:test/test.dart';

import '../support/spec.dart';

/// A parsed note in the shape of spec/fixtures/parsed.json (the Python reference's parse).
Map<String, Object?> describe(Note note) => {
  'meta': note.meta.map((k, v) => MapEntry(k, _value(v))),
  'heading': note.heading,
  'preamble': note.preamble,
  'sections': [
    for (final s in note.sections)
      {
        'heading': s.heading,
        'key': s.key,
        'entries': [for (final e in s.entries) _entry(e)],
      },
  ],
};

Object? _value(Object? v) => switch (v) {
  final DateTime date => {'date': isoDate(date)},
  final List<Object?> list => [for (final x in list) _value(x)],
  _ => v,
};

Map<String, Object?> _entry(NoteEntry e) => switch (e) {
  Decision() => {
    'type': 'decision',
    'date': isoDate(e.date),
    'topic': e.topic,
    'text': e.text,
    'value': e.value,
    'reason': e.reason,
    'superseded': e.superseded == null ? null : isoDate(e.superseded!),
  },
  Entry() => {'type': 'entry', 'date': isoDate(e.date), 'text': e.text},
  Todo() => {'type': 'todo', 'date': isoDate(e.date!), 'text': e.text, 'done': e.done},
  Reminder() => {'type': 'reminder', 'date': isoDate(e.date), 'time': e.time, 'text': e.text},
  Raw() => {'type': 'raw', 'text': e.text},
};

void main() {
  final reference = jsonDecode(
    File('${specFixtures().parent.path}/parsed.json').readAsStringSync(),
  ) as Map<String, Object?>;

  for (final MapEntry(key: name, value: raw) in fixtureBytes().entries) {
    test('$name parses exactly like the reference', () {
      expect(describe(parse(utf8.decode(raw))), reference[name]);
    });
  }

  test('the reference covers every fixture', () {
    expect(reference.keys.toList(), fixtureBytes().keys.toList());
  });

  test('an undated todo goes past the reference on purpose: no fixture has one', () {
    // The Python reference read `- [ ] text` as a raw line; Notelore reads it as a todo
    // (docs/note-format.md). A fixture with one would no longer match parsed.json.
    for (final MapEntry(key: name, value: raw) in fixtureBytes().entries) {
      final todos = [
        for (final s in parse(utf8.decode(raw)).sections) ...s.entries.whereType<Todo>(),
      ];
      expect(todos.where((t) => t.date == null), isEmpty, reason: name);
    }
    final note = parse('---\ntitle: N\n---\n# N\n\n## Todo\n- [ ] Buy a padlock\n');
    final undated = note.sections.single.entries.single;
    expect(undated, isA<Todo>().having((t) => t.date, 'date', isNull));
  });
}
