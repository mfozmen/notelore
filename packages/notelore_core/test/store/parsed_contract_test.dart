import 'dart:convert';
import 'dart:io';

import 'package:notelore_core/src/store/format.dart';
import 'package:test/test.dart';

import '../support/spec.dart';

/// A parsed note in the shape spec/tools/generate_parsed.py writes for the reference.
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
  Todo() => {'type': 'todo', 'date': isoDate(e.date), 'text': e.text, 'done': e.done},
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
}
