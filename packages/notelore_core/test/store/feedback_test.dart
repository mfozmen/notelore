import 'dart:convert';
import 'dart:io';

import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('feedback_'));
  tearDown(() => dir.deleteSync(recursive: true));

  final earlier = <Map<String, Object?>>[
    {'role': 'user', 'content': 'Old question'},
    {'role': 'assistant', 'content': 'Old answer'},
  ];
  final turn = <Map<String, Object?>>[
    {'role': 'user', 'content': 'Kahve aldım'},
    {
      'role': 'assistant',
      'content': [
        {
          'type': 'tool_use',
          'id': 't1',
          'name': 'complete_todo',
          'input': {'slug': 'a'},
        },
      ],
    },
    {
      'role': 'user',
      'content': [
        {'type': 'tool_result', 'tool_use_id': 't1', 'content': 'ok'},
      ],
    },
    {'role': 'assistant', 'content': 'Tamam.'},
  ];

  test('keeps the last turn, the model and what was expected, in a synced folder (#753)', () {
    final rel = saveFeedback(
      dir.path,
      [...earlier, ...turn],
      model: 'chatgpt gpt-6.1-sol',
      expected: 'Should have added an entry',
      now: DateTime.utc(2026, 11, 6, 9, 5, 7),
    );
    expect(rel, '.notelore/feedback/2026-11-06T090507Z.md');
    final text = File(p.join(dir.path, rel)).readAsStringSync();
    expect(text, startsWith('# Feedback, 2026-11-06T090507Z\n\n'));
    expect(text, contains('- Model: chatgpt gpt-6.1-sol\n'));
    expect(text, contains('- Expected: Should have added an entry\n'));
    final json = RegExp(r'```json\n([\s\S]*)\n```\n$').firstMatch(text)![1]!;
    expect(jsonDecode(json), turn); // the earlier turn is not in it
  });

  test("the agent's reminder inside a turn is not where the turn starts (#756)", () {
    final reminded = [
      ...turn,
      {
        'role': 'user',
        'content': [
          {
            'type': 'text',
            'text': emptyNoteReminder(['topics/a.md', 'topics/b.md']),
          },
        ],
      },
      {'role': 'assistant', 'content': 'Yazdım.'},
    ];
    final rel = saveFeedback(dir.path, reminded, model: 'm', now: DateTime.utc(2026, 11, 6));
    final text = File(p.join(dir.path, rel)).readAsStringSync();
    final json = RegExp(r'```json\n([\s\S]*)\n```\n$').firstMatch(text)![1]!;
    expect(jsonDecode(json), reminded);
  });

  test('without an expectation, a dash; a second report the same second gets its own file', () {
    final now = DateTime.utc(2026, 11, 6);
    final first = saveFeedback(dir.path, turn, model: 'm', now: now);
    final second = saveFeedback(dir.path, turn, model: 'm', expected: '  ', now: now);
    expect(second, '.notelore/feedback/2026-11-06T000000Z-2.md');
    expect(File(p.join(dir.path, first)).readAsStringSync(), contains('- Expected: —\n'));
    expect(File(p.join(dir.path, second)).readAsStringSync(), contains('- Expected: —\n'));
  });

  test("a picture's data is left out of the file", () {
    final rel = saveFeedback(
      dir.path,
      [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'Bunu kaydet'},
            {
              'type': 'image',
              'source': {'type': 'base64', 'data': 'QUJD'},
            },
          ],
        },
      ],
      model: 'm',
      now: DateTime.utc(2026),
    );
    final text = File(p.join(dir.path, rel)).readAsStringSync();
    expect(text, contains('Bunu kaydet'));
    expect(text, contains('"type": "image"'));
    expect(text, isNot(contains('QUJD')));
  });

  test('a conversation with no user message is refused', () {
    expect(
      () => saveFeedback(dir.path, const [], model: 'm', now: DateTime.utc(2026)),
      throwsArgumentError,
    );
  });
  test('a test-space report says so (#832)', () {
    final rel = saveFeedback(
      dir.path,
      turn,
      model: 'ollama notelore-qwen3-4b-v8',
      space: 'test',
      now: DateTime.utc(2026, 11, 8, 10),
    );
    expect(File(p.join(dir.path, rel)).readAsStringSync(), contains('- Space: test\n'));
  });
}
