import 'dart:convert';

import 'package:notelore_core/src/eval.dart';
import 'package:test/test.dart';

import 'agent_test.dart' show ScriptedProvider, text, toolUse;

const _mopsos = '''---
title: Mopsos
kind: project
created: 2026-09-12
updated: 2026-09-30
tags: []
---
# Mopsos

## Notes
- 2026-09-15: Hit rate is calculated weekly.
''';

EvalCase _case(Map<String, Object?> json) => EvalCase.fromJson(json);

void main() {
  final filing = _case({
    'id': 'file-1',
    'kind': 'filing',
    'lang': 'en',
    'notes': {'projects/mopsos.md': _mopsos},
    'message': 'Mopsos: we switch the hit rate to daily.',
    'expect': {
      'tools': ['add_note_entry'],
      'notes': {
        r'^projects/mopsos\.md$': ['daily'],
      },
    },
  });

  test('cases load from JSON, with every expectation optional', () {
    final cases = loadCases(
      jsonEncode([
        {
          'id': 'q',
          'kind': 'question',
          'lang': 'tr',
          'message': 'Ne vardı?',
          'expect': <String, Object?>{},
        },
      ]),
    );
    expect(cases.single.id, 'q');
    expect(cases.single.notes, isEmpty);
    expect(cases.single.expect.tools, isEmpty);
    expect(cases.single.expect.answer, isEmpty);
    expect(cases.single.expect.notes, isEmpty);
  });

  test('a file can share its notes: every case starts from them unless it has its own', () {
    final cases = loadCases(
      jsonEncode({
        'notes': {'projects/mopsos.md': _mopsos},
        'cases': [
          {'id': 'a', 'kind': 'k', 'lang': 'en', 'message': 'm', 'expect': <String, Object?>{}},
          {
            'id': 'b',
            'kind': 'k',
            'lang': 'en',
            'message': 'm',
            'notes': <String, String>{},
            'expect': <String, Object?>{},
          },
        ],
      }),
    );
    expect(cases.first.notes.keys, ['projects/mopsos.md']);
    expect(cases.last.notes, isEmpty);
  });

  test('a turn that files the fact in the right note passes', () async {
    final provider = ScriptedProvider([
      toolUse('add_note_entry', 't1', {'slug': 'mopsos', 'text': 'Hit rate is now daily.'}),
      text('Saved to Mopsos.'),
    ]);
    final result = await runCase(filing, provider);
    expect(result.passed, isTrue, reason: '${result.problems}');
    expect(result.tools, ['add_note_entry']);
    expect(result.changed, ['projects/mopsos.md']);
  });

  test('a missing tool, a write elsewhere or a missing fact fails, saying why', () async {
    final provider = ScriptedProvider([
      toolUse('create_note', 't1', {'kind': 'topic', 'title': 'Hit rate'}),
      text('Done.'),
    ]);
    final result = await runCase(filing, provider);
    expect(result.passed, isFalse);
    expect(result.problems, [
      'did not call add_note_entry',
      'wrote topics/hit-rate.md, which it should not have',
      r'no changed note matching ^projects/mopsos\.md$ contains "daily"',
    ]);
  });

  test('an answer is checked for its facts; a question must not write', () async {
    final question = _case({
      'id': 'q-1',
      'kind': 'question',
      'lang': 'en',
      'notes': {'projects/mopsos.md': _mopsos},
      'message': 'How often is the hit rate calculated?',
      'expect': {
        'answer': ['weekly'],
      },
    });
    final right = await runCase(question, ScriptedProvider([text('Weekly, on Sundays.')]));
    expect(right.passed, isTrue, reason: '${right.problems}');
    final wrong = await runCase(
      question,
      ScriptedProvider([
        toolUse('add_note_entry', 't1', {'slug': 'mopsos', 'text': 'asked'}),
        text('Daily.'),
      ]),
    );
    expect(wrong.problems, [
      'wrote projects/mopsos.md, which it should not have',
      'the answer lacks "weekly"',
    ]);
  });

  test('a provider error is a failed case, not a crash', () async {
    final result = await runCase(filing, ScriptedProvider([]));
    expect(result.passed, isFalse);
    expect(result.problems.single, startsWith('error: '));
  });

  test('the report gives accuracy per kind and overall', () async {
    final pass = await runCase(
      filing,
      ScriptedProvider([
        toolUse('add_note_entry', 't1', {'slug': 'mopsos', 'text': 'daily now'}),
        text('ok'),
      ]),
    );
    final fail = await runCase(filing, ScriptedProvider([text('ok')]));
    final report = summarize([pass, fail]);
    expect(report, contains('filing: 1/2 (50%)'));
    expect(report, contains('all: 1/2 (50%)'));
    expect(report, contains('FAIL file-1: did not call add_note_entry'));
  });
}
