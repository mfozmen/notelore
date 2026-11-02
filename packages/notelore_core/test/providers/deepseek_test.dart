import 'package:notelore_core/src/providers/base.dart';
import 'package:notelore_core/src/providers/deepseek.dart';
import 'package:notelore_core/src/providers/http.dart';
import 'package:notelore_core/src/providers/openai.dart';
import 'package:test/test.dart';

import 'base_test.dart' show conversation, tool;
import 'fake_api.dart';

void main() {
  late Api api;
  setUp(() => api = Api());

  test('turn posts the Chat Completions API with tool calls and results', () async {
    api.answers.add({
      'choices': [
        {
          'message': {
            'role': 'assistant',
            'content': 'done',
            'tool_calls': [
              {
                'id': 't2',
                'type': 'function',
                'function': {'name': 'read_note', 'arguments': '{"slug":"y"}'},
              },
            ],
          },
          'finish_reason': 'tool_calls',
        },
      ],
      'usage': {'prompt_tokens': 120, 'completion_tokens': 30},
    });
    final response = await DeepSeekProvider(
      'sk-deep',
      'deepseek-flash',
      transport: api.call,
    ).turn('be brief', conversation, [tool]);
    expect(response.stopReason, 'tool_use');
    expect(response.content, [
      {'type': 'text', 'text': 'done'},
      {
        'type': 'tool_use',
        'id': 't2',
        'name': 'read_note',
        'input': {'slug': 'y'},
      },
    ]);
    expect((response.usage!.input, response.usage!.output), (120, 30));

    final call = api.last;
    expect((call['method'], call['url']), ('POST', deepSeekChat));
    expect(call['headers'], {'Authorization': 'Bearer sk-deep'});
    expect(call['body'], {
      'model': 'deepseek-flash',
      'messages': [
        {'role': 'system', 'content': 'be brief'},
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
          ],
        },
        {'role': 'tool', 'tool_call_id': 't1', 'content': 'ok'},
      ],
      'stream': false,
      'thinking': {'type': 'disabled'},
      'tools': functionTools([tool]),
    });
    expect(call['timeout'], const Duration(seconds: 120));
  });

  test('a cut-short answer is marked and its tool call does not run', () async {
    api.answers.add({
      'choices': [
        {
          'message': {
            'content': 'half',
            'tool_calls': [
              {
                'id': 't3',
                'type': 'function',
                'function': {'name': 'read_note', 'arguments': '{"slug":"y"}'},
              },
            ],
          },
          'finish_reason': 'length',
        },
      ],
    });
    final response = await DeepSeekProvider('sk', 'm', transport: api.call).turn('', [], []);
    expect(response.stopReason, 'end_turn');
    expect(response.content.last, {'type': 'text', 'text': '[The model stopped early: length.]'});
  });

  test('images go as OpenAI image content parts', () async {
    api.answers.add({
      'choices': [
        {
          'message': {'content': 'a cat'},
          'finish_reason': 'stop',
        },
      ],
    });
    final response = await DeepSeekProvider('sk', 'm', transport: api.call).turn('', [
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'look'},
          imageBlock('image/png', [1, 2, 3]),
        ],
      },
    ], []);
    expect(response.stopReason, 'end_turn');
    expect(response.content, [
      {'type': 'text', 'text': 'a cat'},
    ]);
    final body = api.last['body']! as Map<String, Object?>;
    expect(body.containsKey('tools'), isFalse);
    expect(body['messages'], [
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'look'},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:image/png;base64,AQID'},
          },
        ],
      },
    ]);
  });

  test('an answer without choices is empty, and unreported usage is not invented', () async {
    api.answers
      ..add(<String, Object?>{})
      ..add({
        'choices': [
          {
            'message': {
              'content': '',
              'tool_calls': [
                {
                  'function': {'name': 'read_note', 'arguments': 'not json'},
                },
              ],
            },
            'finish_reason': 'tool_calls',
          },
        ],
      });
    final provider = DeepSeekProvider('sk', 'm', transport: api.call);
    final empty = await provider.turn('', [], []);
    expect(empty.content, isEmpty);
    expect(empty.stopReason, 'end_turn');
    expect(empty.usage, isNull);

    final response = await provider.turn('', [], []);
    expect(response.stopReason, 'tool_use');
    expect(response.usage, isNull);
    expect(response.content.single['name'], 'read_note');
    expect(response.content.single['input'], {'__raw': 'not json'});
    expect('${response.content.single['id']}', startsWith('toolu_'));
  });

  test('transport errors pass through without the key', () async {
    api.answers
      ..add(const HttpError(401, 'invalid key'))
      ..add(const NetworkError('no route to host'));
    final provider = DeepSeekProvider('sk-secret', 'm', transport: api.call);
    await expectLater(provider.turn('', [], []), throwsA(isA<HttpError>()));
    await expectLater(provider.turn('', [], []), throwsA(isA<NetworkError>()));
  });

  test('another OpenAI-compatible endpoint: its URL, and no DeepSeek thinking switch', () async {
    final api = Api()
      ..answers.add({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 'ok'},
            'finish_reason': 'stop',
          },
        ],
      });
    await DeepSeekProvider(
      'k',
      'glm-5.3',
      transport: api.call,
      url: 'https://example.test/v1/chat/completions',
      disableThinking: false,
    ).turn('', [
      {'role': 'user', 'content': 'hi'},
    ], []);
    expect(api.last['url'], 'https://example.test/v1/chat/completions');
    expect((api.last['body']! as Map).containsKey('thinking'), isFalse);
  });
}
