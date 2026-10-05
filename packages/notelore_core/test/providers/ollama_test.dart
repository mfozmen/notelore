import 'package:notelore_core/src/providers/ollama.dart';
import 'package:test/test.dart';

import 'base_test.dart' show conversation, tool;
import 'fake_api.dart';

void main() {
  test('the host comes from OLLAMA_HOST', () {
    expect(ollamaHost({}), 'http://localhost:11434');
    expect(ollamaHost({'OLLAMA_HOST': 'http://box:1/'}), 'http://box:1');
    expect(ollamaHost(), isNotEmpty); // the process environment
  });

  test('toOllama translates by tool name', () {
    expect(toOllama(conversation), [
      {'role': 'user', 'content': 'hi'},
      {
        'role': 'assistant',
        'content': 'checking',
        'tool_calls': [
          {
            'function': {
              'name': 'read_note',
              'arguments': {'slug': 'x'},
            },
          },
          {
            'function': {'name': 'no-id-is-skipped', 'arguments': <String, Object?>{}},
          },
        ],
      },
      {'role': 'tool', 'content': 'ok', 'tool_name': 'read_note'},
    ]);
    expect(
      toOllama([
        {'role': 'assistant', 'content': <Object?>[]},
      ]),
      [
        {'role': 'assistant', 'content': ''},
      ],
    );
  });

  test('fromOllama variants', () {
    expect(fromOllama({}).content, isEmpty);
    final text = fromOllama({
      'message': {'content': 'hello'},
    });
    expect(text.content, [
      {'type': 'text', 'text': 'hello'},
    ]);
    expect(text.stopReason, 'end_turn');
    final tool = fromOllama({
      'message': {
        'content': '',
        'tool_calls': [
          {
            'function': {
              'name': 'read_note',
              'arguments': {'slug': 'x'},
            },
          },
          {
            'function': {'name': 'search_notes', 'arguments': '{"query": "q"}'}, // some models
          },
        ],
      },
    });
    expect(tool.stopReason, 'tool_use');
    expect(tool.content.map((b) => b['input']), [
      {'slug': 'x'},
      {'query': 'q'},
    ]);
    expect(tool.content.every((b) => '${b['id']}'.startsWith('toolu_')), isTrue);
  });

  test('turn posts /api/chat without streaming', () async {
    final api = Api()
      ..answers.addAll([
        {
          'message': {'content': 'ok'},
        },
        {
          'message': {'content': 'ok'},
        },
      ]);
    final provider = OllamaProvider('llama-x', host: 'http://box:1', transport: api.call);
    final hi = [
      {'role': 'user', 'content': 'hi'},
    ];
    expect((await provider.turn('be brief', hi, [tool])).content, [
      {'type': 'text', 'text': 'ok'},
    ]);
    final call = api.last;
    expect((call['method'], call['url']), ('POST', 'http://box:1/api/chat'));
    final body = call['body']! as Map<String, Object?>;
    expect(body['stream'], isFalse);
    expect(body['model'], 'llama-x');
    expect((body['messages']! as List).first, {'role': 'system', 'content': 'be brief'});
    expect(((body['tools']! as List).first as Map)['function'], containsPair('name', 'read_note'));
    expect(call['timeout'], const Duration(seconds: 180));
    await provider.turn('', hi, []);
    final second = api.last['body']! as Map<String, Object?>;
    expect(second.containsKey('tools'), isFalse);
    expect(second['messages'], hi);
  });
}
