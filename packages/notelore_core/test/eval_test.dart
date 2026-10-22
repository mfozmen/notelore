import 'dart:convert';

import 'package:notelore_core/src/agent.dart' show slimSystemPrompt, systemPrompt;
import 'package:notelore_core/src/eval.dart';
import 'package:notelore_core/src/providers/base.dart' show Message;
import 'package:notelore_core/src/tools.dart' show noteTools, slimTools;
import 'package:test/test.dart';

import 'agent_test.dart' show ScriptedProvider, text, toolUse;

const _futbol = '''---
title: Futbol
kind: topic
created: 2026-10-01
updated: 2026-10-01
tags: []
---
# Futbol

## Notes
''';

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

  test('a passing turn becomes a training example: system, tools and the whole exchange', () async {
    final result = await runCase(
      filing,
      ScriptedProvider([
        toolUse('add_note_entry', 't1', {'slug': 'mopsos', 'text': 'Hit rate is now daily.'}),
        text('Saved to Mopsos.'),
      ]),
    );
    final example = trainingExample(result);
    final messages = (example['messages']! as List).cast<Map<String, Object?>>();
    expect(messages.map((m) => m['role']), ['system', 'user', 'assistant', 'tool', 'assistant']);
    // The minute the model is told, so a relative reminder time has one answer (#434).
    expect(messages.first['content'], endsWith('It is now 2026-10-18 14:00, local time.'));
    expect(messages.first['content'], contains('Notelore'));
    expect(messages[1]['content'], filing.message);
    final call = ((messages[2]['tool_calls']! as List).single as Map)['function'] as Map;
    expect(call['name'], 'add_note_entry');
    expect(messages[3]['tool_name'], 'add_note_entry');
    expect(messages.last['content'], 'Saved to Mopsos.');
    expect(
      (example['tools']! as List).map((t) => ((t as Map)['function'] as Map)['name']),
      contains('add_note_entry'),
    );
    jsonEncode(example); // one JSONL line
  });

  test('an example gets the current prompt and tools, its turns kept as they were', () {
    final old = {
      'messages': [
        {'role': 'system', 'content': 'an older prompt'},
        {'role': 'user', 'content': 'hi'},
        {'role': 'assistant', 'content': 'Hello.'},
      ],
      'tools': <Object?>[],
    };
    final now = reprompted(old);
    final messages = (now['messages']! as List).cast<Map<String, Object?>>();
    expect(messages.first, {'role': 'system', 'content': systemPrompt(evalNow)});
    expect(messages.skip(1), (old['messages']! as List).skip(1));
    expect(now['tools'], hasLength(noteTools.length));
    final slim = reprompted(old, slim: true);
    expect(((slim['messages']! as List).first as Map)['content'], slimSystemPrompt(evalNow));
    expect(slim['tools'], hasLength(slimTools.length));
    // An example without a system message gets one in front.
    final bare = reprompted({
      'messages': [
        {'role': 'user', 'content': 'hi'},
      ],
    });
    expect((bare['messages']! as List).map((m) => (m as Map)['role']), ['system', 'user']);
  });

  group('a case with web results gets a search that answers with them (#478)', () {
    final derby = _case({
      'id': 'plan-1',
      'kind': 'plan',
      'lang': 'tr',
      'notes': <String, String>{},
      'message': 'haftaya derbiyi izleyeceğim',
      'search': ['Derbi: 25 Ekim 2026 Pazar, saat 20:00.'],
      'expect': {
        'tools': ['add_reminder'],
      },
    });

    test('the search is offered and answers with the case results', () async {
      final provider = ScriptedProvider([
        toolUse('web_search', 't1', {'query': 'derbi tarihi'}),
        text('25 Ekim 20:00.'),
      ]);
      final result = await runCase(derby, provider);
      expect(provider.turns.first.$3.map((t) => t.name), contains('web_search'));
      final found = provider.turns.last.$2.last['content']! as List;
      expect((found.single as Map)['content'], contains('25 Ekim 2026 Pazar, saat 20:00'));
      expect(result.problems, ['did not call add_reminder']);
      expect(derby.search, hasLength(1));
      expect(filing.search, isNull);
      // A case without results offers no search.
      final plain = ScriptedProvider([text('ok')]);
      await runCase(filing, plain);
      expect(plain.turns.first.$3.map((t) => t.name), isNot(contains('web_search')));
    });
  });

  group('a tool that fails once, and words the answer must not have (#474)', () {
    final flaky = _case({
      'id': 'fail-1',
      'kind': 'recovery',
      'lang': 'en',
      'notes': {'projects/mopsos.md': _mopsos},
      'message': 'Mopsos: we switch the hit rate to daily.',
      'fail_first_call': true,
      'expect': {
        'notes': {
          r'^projects/mopsos\.md$': ['daily'],
        },
        'answer_not': ['add_note_entry', 'sorry'],
      },
    });

    test('the first call gets an error; a retry works and passes', () async {
      final provider = ScriptedProvider([
        toolUse('add_note_entry', 't1', {'slug': 'mopsos', 'text': 'Hit rate is now daily.'}),
        toolUse('add_note_entry', 't2', {'slug': 'mopsos', 'text': 'Hit rate is now daily.'}),
        text('Saved to Mopsos.'),
      ]);
      final result = await runCase(flaky, provider);
      expect(result.passed, isTrue, reason: '${result.problems}');
      final first = provider.turns[1].$2.last['content']! as List;
      expect((first.single as Map)['content'], startsWith('Error:'));
      expect(flaky.failFirstCall, isTrue);
      expect(filing.failFirstCall, isFalse);
      // The error was the case's own, and the recovery is what v4 should learn:
      // the turn is kept for training. A real tool error still leaves a turn out.
      expect(trainingIssues(result.messages), isEmpty);
    });

    test('naming the tool, or giving up to the user, fails', () async {
      final result = await runCase(
        flaky,
        ScriptedProvider([
          toolUse('add_note_entry', 't1', {'slug': 'mopsos', 'text': 'Daily.'}),
          text("I'm sorry, add_note_entry failed. What should I do?"),
        ]),
      );
      expect(result.problems, [
        r'no changed note matching ^projects/mopsos\.md$ contains "daily"',
        'the answer has "add_note_entry"',
        'the answer has "sorry"',
      ]);
    });
  });

  group('lines a changed note must not have (#499)', () {
    final match = _case({
      'id': 'rem-title',
      'kind': 'reminder',
      'lang': 'tr',
      'notes': {'topics/futbol.md': _futbol},
      'message': "Yarın 21.30'da Fenerbahçe–Galatasaray maçını izleyeceğim, hatırlat.",
      'expect': {
        'notes': {
          r'^topics/futbol\.md$': ['2026-10-19 21:30'],
        },
        'lines_not': [r'^- \d{4}-\d\d-\d\d \d\d:\d\d(?:-\d\d:\d\d)?: (.{50,}|.*\d[.:]\d\d)'],
      },
    });

    Future<EvalResult> remind(String title) => runCase(
      match,
      ScriptedProvider([
        toolUse('add_reminder', 't1', {'slug': 'futbol', 'at': '2026-10-19 21:30', 'text': title}),
        text('Hatırlatacağım.'),
      ]),
    );

    test('a short title passes', () async {
      final result = await remind('Fenerbahçe–Galatasaray maçı');
      expect(result.passed, isTrue, reason: '${result.problems}');
    });

    test('a sentence with the time in it fails', () async {
      final result = await remind(
        "Fenerbahçe–Galatasaray maçını izle; maç Türkiye saatiyle 21.30'da başlayacak.",
      );
      expect(result.problems, [
        r'topics/futbol.md has a line matching ^- \d{4}-\d\d-\d\d \d\d:\d\d(?:-\d\d:\d\d)?: (.{50,}|.*\d[.:]\d\d)',
      ]);
    });
  });

  test('a slim run asks with the slim prompt and tools, and trains on them (#447)', () async {
    final provider = ScriptedProvider([
      toolUse('add_note_entry', 't1', {'slug': 'mopsos', 'text': 'Hit rate is now daily.'}),
      text('Saved to Mopsos.'),
    ]);
    final result = await runCase(filing, provider, slim: true);
    expect(result.passed, isTrue, reason: '${result.problems}');
    expect(provider.turns.first.$1, slimSystemPrompt(evalNow));
    expect(provider.turns.first.$3, slimTools);
    final example = trainingExample(result);
    final messages = (example['messages']! as List).cast<Map<String, Object?>>();
    expect(messages.first['content'], slimSystemPrompt(evalNow));
    expect(example['tools'], hasLength(slimTools.length));
  });

  test('training issues detect tool errors and repeated calls by arguments', () {
    final messages = [
      {
        'role': 'assistant',
        'content': [
          {
            'type': 'tool_use',
            'name': 'list_notes',
            'input': {'kind': 'topic', 'limit': 2},
          },
        ],
      },
      {
        'role': 'user',
        'content': [
          {'type': 'tool_result', 'content': 'Error: invalid argument'},
        ],
      },
      {
        'role': 'assistant',
        'content': [
          {
            'type': 'tool_use',
            'name': 'list_notes',
            'input': {'limit': 2, 'kind': 'topic'},
          },
          {
            'type': 'tool_use',
            'name': 'list_notes',
            'input': {'kind': 'project'},
          },
        ],
      },
    ];
    expect(trainingIssues(messages), {TrainingIssue.toolError, TrainingIssue.repeatedCall});
    expect(trainingIssues([messages.last]), isEmpty);
  });

  group('a read repeated with the same result adds nothing: it is dropped, not the turn', () {
    Message call(String id, String name, [Map<String, Object?> input = const {}]) => {
      'type': 'tool_use',
      'id': id,
      'name': name,
      'input': input,
    };
    Message result(String id, String content) => {
      'type': 'tool_result',
      'tool_use_id': id,
      'content': content,
    };
    Message assistant(List<Message> blocks) => {'role': 'assistant', 'content': blocks};
    Message results(List<Message> blocks) => {'role': 'user', 'content': blocks};
    const list = '[{"slug": "mopsos"}]';

    test('a call alone in its step goes with its step', () {
      final messages = [
        {'role': 'user', 'content': 'Mopsos: weekly.'},
        assistant([call('a', 'list_notes')]),
        results([result('a', list)]),
        assistant([call('b', 'list_notes')]),
        results([result('b', list)]),
        assistant([
          call('c', 'add_note_entry', {'slug': 'mopsos', 'text': 'Weekly.'}),
        ]),
        results([result('c', 'ok')]),
        assistant([
          {'type': 'text', 'text': 'Saved.'},
        ]),
      ];
      final collapsed = collapseRepeatedReads(messages);
      expect(collapsed, [...messages.take(3), ...messages.skip(5)]);
      expect(trainingIssues(messages), isEmpty);
    });

    test('a call beside others goes alone, with its result', () {
      final messages = [
        assistant([
          call('a', 'read_note', {'slug': 'x'}),
        ]),
        results([result('a', '# X')]),
        assistant([
          call('b', 'read_note', {'slug': 'x'}),
          call('c', 'read_note', {'slug': 'y'}),
        ]),
        results([result('b', '# X'), result('c', '# Y')]),
      ];
      expect(collapseRepeatedReads(messages).skip(2), [
        assistant([
          call('c', 'read_note', {'slug': 'y'}),
        ]),
        results([result('c', '# Y')]),
      ]);
    });

    test('a read that answered otherwise, or a write, is kept and still counts', () {
      final changed = [
        assistant([call('a', 'list_notes')]),
        results([result('a', '[]')]),
        assistant([call('b', 'list_notes')]),
        results([result('b', list)]), // a note was made in between
      ];
      expect(collapseRepeatedReads(changed), changed);
      expect(trainingIssues(changed), {TrainingIssue.repeatedCall});
      final writes = [
        assistant([
          call('a', 'add_todo', {'slug': 'x', 'text': 'Buy milk'}),
        ]),
        results([result('a', 'ok')]),
        assistant([
          call('b', 'add_todo', {'slug': 'x', 'text': 'Buy milk'}),
        ]),
        results([result('b', 'ok')]),
      ];
      expect(collapseRepeatedReads(writes), writes);
      expect(trainingIssues(writes), {TrainingIssue.repeatedCall});
    });

    test('the training example is the collapsed exchange', () async {
      final result = await runCase(
        filing,
        ScriptedProvider([
          toolUse('list_notes', 't1'),
          toolUse('list_notes', 't2'),
          toolUse('add_note_entry', 't3', {'slug': 'mopsos', 'text': 'Hit rate is now daily.'}),
          text('Saved to Mopsos.'),
        ]),
      );
      final messages = (trainingExample(result)['messages']! as List).cast<Map<String, Object?>>();
      expect(messages.map((m) => m['role']), [
        'system',
        'user',
        'assistant',
        'tool',
        'assistant',
        'tool',
        'assistant',
      ]);
    });
  });

  test('training issues recognize tool error prefixes regardless of case', () {
    expect(
      trainingIssues([
        {
          'role': 'user',
          'content': [
            {'type': 'tool_result', 'content': 'error: invalid argument'},
          ],
        },
      ]),
      {TrainingIssue.toolError},
    );
  });

  test('a missing tool, a write elsewhere or a missing fact fails, saying why', () async {
    final provider = ScriptedProvider([
      toolUse('create_note', 't1', {'kind': 'topic', 'title': 'Hit rate'}),
      toolUse('add_todo', 't2', {'slug': 'hit-rate', 'text': 'Check daily.'}),
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
    expect(summarize([]), 'all: 0/0'); // an empty file reports, it does not crash
  });
}
