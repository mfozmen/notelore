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
    final provider = ScriptedProvider([
      toolUse('add_note_entry', 't1', {'slug': 'mopsos', 'text': 'Hit rate is now daily.'}),
      text('Saved to Mopsos.'),
    ]);
    final result = await runCase(filing, provider);
    final example = trainingExample(result);
    final messages = (example['messages']! as List).cast<Map<String, Object?>>();
    expect(messages.map((m) => m['role']), ['system', 'user', 'assistant', 'tool', 'assistant']);
    // The system text the model was sent, its note list included (#602).
    expect(messages.first['content'], provider.turns.first.$1);
    // The minute the model is told, so a relative reminder time has one answer (#434).
    expect(messages.first['content'], contains('It is now 2026-10-18 14:00, local time.'));
    expect(messages.first['content'], endsWith('- Mopsos: mopsos, project'));
    // Its scenario, so a split keeps one scenario's turns on one side; its note
    // list, so a reprompt keeps it.
    expect(example['id'], 'file-1');
    expect(example['note_list'], result.noteList);
    expect(result.noteList, startsWith('Notes ('));
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
    // An example's note list stays after today's prompt (#602).
    final listed = reprompted({...old, 'note_list': 'Notes:\n- Mopsos: mopsos, project'});
    expect(
      ((listed['messages']! as List).first as Map)['content'],
      '${systemPrompt(evalNow)}\n\nNotes:\n- Mopsos: mopsos, project',
    );
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

  test('a tool the case rules out fails it: a tick nobody asked for (#629)', () async {
    final update = _case({
      'id': 'file-tick',
      'kind': 'filing',
      'lang': 'en',
      'notes': {'projects/mopsos.md': _mopsos},
      'message': 'Mopsos: the hit rate is now daily.',
      'expect': {
        'tools': ['add_note_entry'],
        'tools_not': ['complete_todo'],
        'notes': {
          r'^projects/mopsos\.md$': ['daily'],
        },
      },
    });
    final result = await runCase(
      update,
      ScriptedProvider([
        toolUse('add_note_entry', 't1', {'slug': 'mopsos', 'text': 'Hit rate is now daily.'}),
        toolUse('complete_todo', 't2', {'slug': 'mopsos', 'number': 1}),
        text('Saved to Mopsos.'),
      ]),
    );
    expect(result.problems, ['called complete_todo']);
    expect(filing.expect.toolsNot, isEmpty);
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
    expect(provider.turns.first.$1, startsWith(slimSystemPrompt(evalNow)));
    expect(provider.turns.first.$3, slimTools);
    final example = trainingExample(result);
    final messages = (example['messages']! as List).cast<Map<String, Object?>>();
    expect(messages.first['content'], provider.turns.first.$1);
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

  test("the answer's language: told by its small words, quoted titles left out (#597)", () {
    expect(
      answerLanguage(
        "I've created a new note titled \"Saatleri Ayarlama Enstitüsü\" in your collection of topics.",
      ),
      'en',
    );
    expect(answerLanguage('Bu bilgiyi "Ev Tadilatı" projesine bir not olarak ekledim.'), 'tr');
    expect(answerLanguage('Kaydedildi: Ev Tadilatı.'), isNull); // no small words: no verdict
    expect(answerLanguage(''), isNull);
  });

  test("an answer in another language than the user's fails the case (#597)", () async {
    final turkish = _case({
      'id': 'q-tr',
      'kind': 'question',
      'lang': 'tr',
      'notes': {'projects/mopsos.md': _mopsos},
      'message': "Mopsos'ta isabet oranı ne sıklıkla hesaplanıyor?",
      'expect': {
        'answer': ['weekly'],
      },
    });
    final english = await runCase(
      turkish,
      ScriptedProvider([text('The hit rate is calculated weekly, and that is all I have.')]),
    );
    expect(english.problems, ['the answer is in en, not tr']);
    final quoted = await runCase(
      turkish,
      ScriptedProvider([
        text(
          'Notta "Hit rate is calculated weekly and the team is on it" yazıyor, yani bu haftalık.',
        ),
      ]),
    );
    expect(quoted.passed, isTrue);
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

  test("repeated runs: each run's total, then the kinds over all runs (#597)", () async {
    final pass = await runCase(
      filing,
      ScriptedProvider([
        toolUse('add_note_entry', 't1', {'slug': 'mopsos', 'text': 'daily now'}),
        text('ok'),
      ]),
    );
    final fail = await runCase(filing, ScriptedProvider([text('ok')]));
    final report = summarizeRuns([
      [pass, pass],
      [pass, fail],
    ]);
    expect(report, startsWith('run 1: 2/2 (100%)\nrun 2: 1/2 (50%)\n'));
    expect(report, contains('filing: 3/4 (75%)'));
    expect(report, contains('all: 3/4 (75%)'));
    expect(
      summarizeRuns([
        [fail],
      ]),
      summarize([fail]),
    ); // one run reads as before
    expect(summarizeRuns([[], []]), startsWith('run 1: 0/0\nrun 2: 0/0\n')); // no cases: no crash
  });

  group('first write: the turn stops at its first write, which is scored (#598)', () {
    test('the stopping provider is the model it wraps', () {
      expect(UntilWrite(ScriptedProvider([])).model, 'scripted');
    });

    test('a right write passes without the rest of the turn', () async {
      final provider = ScriptedProvider([
        toolUse('list_notes', 't0', {}),
        toolUse('add_note_entry', 't1', {'slug': 'mopsos', 'text': 'daily now'}),
        text('never asked for'),
      ]);
      final result = await runCase(filing, provider, firstWrite: true);
      expect(result.passed, isTrue);
      expect(provider.turns, hasLength(2)); // stopped before a third model call
      expect(result.action, 'add_note_entry');
      expect(result.wanted, 'add_note_entry');
    });

    test('a note made first does not stop it; the write into it does', () async {
      final firstOfKind = _case({
        'id': 'first',
        'kind': 'collection',
        'lang': 'en',
        'message': 'Reading Piranesi.',
        'expect': {
          'tools': ['create_note'],
          'notes': {
            r'^topics/[^/]*book[^/]*\.md$': ['Piranesi'],
          },
        },
      });
      final result = await runCase(
        firstOfKind,
        ScriptedProvider([
          toolUse('create_note', 't1', {'kind': 'topic', 'title': 'Books'}),
          toolUse('add_note_entry', 't2', {'slug': 'books', 'kind': 'topic', 'text': 'Piranesi'}),
          text('never asked for'),
        ]),
        firstWrite: true,
      );
      expect(result.passed, isTrue);
      expect(result.action, 'add_note_entry');
    });

    test(
      'a write elsewhere, or a failed one followed by none, fails and says what it did',
      () async {
        final wrong = await runCase(
          filing,
          ScriptedProvider([
            toolUse('create_note', 't1', {'kind': 'project', 'title': 'Daily'}),
            toolUse('record_decision', 't2', {'slug': 'daily', 'topic': 'rate', 'value': 'daily'}),
            text('never asked for'),
          ]),
          firstWrite: true,
        );
        expect(wrong.passed, isFalse);
        expect(wrong.action, 'record_decision');
        expect(wrong.problems, contains('did not call add_note_entry'));
        final none = await runCase(
          filing,
          ScriptedProvider([text('Which note?')]),
          firstWrite: true,
        );
        expect(none.action, 'ask');
        final chat = await runCase(
          _case({
            'id': 'chat',
            'kind': 'chat',
            'lang': 'en',
            'message': 'thanks',
            'expect': <String, Object?>{},
          }),
          ScriptedProvider([text('You are welcome.')]),
          firstWrite: true,
        );
        expect((chat.wanted, chat.action, chat.passed), ('none', 'none', true));
      },
    );

    test('the report counts wanted against done for the cases that failed', () async {
      final asked = await runCase(
        filing,
        ScriptedProvider([text('Which note?')]),
        firstWrite: true,
      );
      final elsewhere = await runCase(
        filing,
        ScriptedProvider([
          toolUse('add_note_entry', 't1', {'slug': 'mopsos', 'text': 'weekly still'}),
        ]),
        firstWrite: true,
      );
      expect(
        confusion([elsewhere]),
        'wanted → done, failed cases:\n  add_note_entry, but the note or answer was wrong: 1',
      );
      final report = confusion([asked, asked]);
      expect(report, 'wanted → done, failed cases:\n  add_note_entry → ask: 2');
      expect(confusion([]), isEmpty);
    });
  });
}
