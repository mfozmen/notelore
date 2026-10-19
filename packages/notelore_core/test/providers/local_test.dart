import 'package:notelore_core/src/providers/base.dart';
import 'package:notelore_core/src/providers/local.dart';
import 'package:test/test.dart';

/// A model on the device, scripted: what it was asked, and what it answers.
class FakeEngine implements LocalEngine {
  FakeEngine(this.answers);

  final List<Map<String, Object?>> answers;
  final asked = <(List<Map<String, Object?>>, List<Map<String, Object?>>)>[];

  @override
  Future<Map<String, Object?>> chat(
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools,
  ) async {
    asked.add((messages, tools));
    return answers.removeAt(0);
  }

  @override
  Future<void> dispose() async {}
}

const _tools = [
  Tool('add_note_entry', 'Append a dated note.', {
    'type': 'object',
    'properties': {
      'slug': {'type': 'string'},
      'text': {'type': 'string'},
    },
    'required': ['slug', 'text'],
  }),
];

void main() {
  test('a model the device cannot run says why', () {
    expect('${const LocalModelFailed('out of memory')}', 'out of memory');
  });

  test(
    'a turn on the device: the prompt, the history and the tools in, a tool call out (#328)',
    () async {
      final engine = FakeEngine([
        {
          'message': {
            'content': '',
            'tool_calls': [
              {
                'function': {
                  'name': 'add_note_entry',
                  'arguments': {'slug': 'mopsos', 'text': 'Weekly.'},
                },
              },
            ],
          },
          'prompt_eval_count': 2707,
          'eval_count': 31,
        },
      ]);
      final provider = LocalProvider('notelore-qwen3-4b', engine);
      expect(provider.model, 'notelore-qwen3-4b');
      final reply = await provider.turn('You are Notelore.', [
        {'role': 'user', 'content': 'Mopsos: weekly.'},
      ], _tools);
      final (messages, tools) = engine.asked.single;
      expect(messages, [
        {'role': 'system', 'content': 'You are Notelore.'},
        {'role': 'user', 'content': 'Mopsos: weekly.'},
      ]);
      expect((tools.single['function']! as Map)['name'], 'add_note_entry');
      expect(reply.stopReason, 'tool_use');
      final call = reply.content.single;
      expect(call['name'], 'add_note_entry');
      expect(call['input'], {'slug': 'mopsos', 'text': 'Weekly.'});
      expect(call['id'], isA<String>().having((id) => id, 'id', isNotEmpty));
      expect((reply.usage!.input, reply.usage!.output), (2707, 31));
    },
  );

  test('a tool result goes back by its tool, and the answer comes without its reasoning', () async {
    final engine = FakeEngine([
      {
        'message': {'content': 'Let me see.</think>Saved to Mopsos.'},
      },
    ]);
    final reply = await LocalProvider('m', engine).turn('', [
      {'role': 'user', 'content': 'Mopsos: weekly.'},
      {
        'role': 'assistant',
        'content': [
          {
            'type': 'tool_use',
            'id': 't1',
            'name': 'add_note_entry',
            'input': {'slug': 'mopsos', 'text': 'Weekly.'},
          },
        ],
      },
      {
        'role': 'user',
        'content': [
          {'type': 'tool_result', 'tool_use_id': 't1', 'content': 'ok'},
        ],
      },
    ], const []);
    final (messages, tools) = engine.asked.single;
    expect(messages.first['role'], 'user'); // no empty system message
    expect(messages.last, {'role': 'tool', 'content': 'ok', 'tool_name': 'add_note_entry'});
    expect(tools, isEmpty);
    expect(reply.stopReason, 'end_turn');
    expect(reply.content, [
      {'type': 'text', 'text': 'Saved to Mopsos.'},
    ]);
    expect(reply.usage, isNull);
  });
}
