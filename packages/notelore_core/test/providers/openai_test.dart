import 'package:notelore_core/src/providers/openai.dart';
import 'package:test/test.dart';

import 'base_test.dart' show conversation, tool;
import 'fake_api.dart';

Map<String, Object?> completion({
  String? content,
  List<Object?>? toolCalls,
  String? finish = 'stop',
}) => {
  'choices': [
    {
      'message': {'role': 'assistant', 'content': content, 'tool_calls': ?toolCalls},
      'finish_reason': finish,
    },
  ],
};

void main() {
  test('toOpenAI translates tool calls and results', () {
    expect(toOpenAI(conversation), [
      {'role': 'user', 'content': 'hi'},
      {
        'role': 'assistant',
        'content': 'checking',
        'tool_calls': [
          {
            'id': 't1',
            'type': 'function',
            'function': {'name': 'read_note', 'arguments': '{"slug":"x"}'},
          },
          {
            'id': '',
            'type': 'function',
            'function': {'name': 'no-id-is-skipped', 'arguments': '{}'},
          },
        ],
      },
      {'role': 'tool', 'tool_call_id': 't1', 'content': 'ok'},
    ]);
    expect(
      toOpenAI([
        {'role': 'assistant', 'content': <Object?>[]},
      ]),
      [
        {'role': 'assistant', 'content': null},
      ],
    );
  });

  test('fromOpenAI variants', () {
    expect(fromOpenAI({'choices': <Object?>[]}).content, isEmpty);
    expect(fromOpenAI({}).content, isEmpty);
    final text = fromOpenAI(completion(content: 'hello'));
    expect(text.content, [
      {'type': 'text', 'text': 'hello'},
    ]);
    expect(text.stopReason, 'end_turn');
    final call = {
      'id': 'c1',
      'type': 'function',
      'function': {'name': 'read_note', 'arguments': '{"slug": "x"}'},
    };
    final tool = fromOpenAI(completion(toolCalls: [call], finish: 'tool_calls'));
    expect(tool.stopReason, 'tool_use');
    expect(tool.content, [
      {
        'type': 'tool_use',
        'id': 'c1',
        'name': 'read_note',
        'input': {'slug': 'x'},
      },
    ]);
    final cut = fromOpenAI(completion(content: 'partial', finish: 'length'));
    expect(cut.content[1]['text'], '[The model stopped early: length.]');
    expect(fromOpenAI(completion(content: 'x', finish: null)).content, [
      {'type': 'text', 'text': 'x'},
    ]);
    expect(
      fromOpenAI({
        'choices': [
          {'finish_reason': 'stop'},
        ],
      }).content,
      isEmpty,
    );
  });

  test('turn posts chat completions', () async {
    final api = Api()..answers.addAll([completion(content: 'ok'), completion(content: 'ok')]);
    final provider = OpenAIProvider('sk', 'gpt-x', transport: api.call);
    final hi = [
      {'role': 'user', 'content': 'hi'},
    ];
    expect((await provider.turn('be brief', hi, [tool])).content, [
      {'type': 'text', 'text': 'ok'},
    ]);
    final call = api.last;
    expect((call['method'], call['url']), ('POST', openAIApi));
    expect(call['headers'], {'Authorization': 'Bearer sk'});
    final body = call['body']! as Map<String, Object?>;
    expect(body['model'], 'gpt-x');
    expect((body['messages']! as List).first, {'role': 'system', 'content': 'be brief'});
    expect((body['tools']! as List).first, {
      'type': 'function',
      'function': {
        'name': 'read_note',
        'description': 'Read a note',
        'parameters': tool.inputSchema,
      },
    });
    await provider.turn('', hi, []);
    final second = api.last['body']! as Map<String, Object?>;
    expect(second.containsKey('tools'), isFalse);
    expect(second['messages'], hi); // no empty system message
  });
}
