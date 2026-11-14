import 'package:notelore_core/src/providers/base.dart';
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

  test('fromOllama drops the reasoning a thinking model leaks into its answer (#348)', () {
    String? answer(String content) =>
        fromOllama({
              'message': {'content': content, 'thinking': 'hidden'},
            }).content.firstOrNull?['text']
            as String?;
    expect(answer('<think>\nOkay, let me see.\n</think>\n\nSaved it.'), 'Saved it.');
    expect(answer('Okay, let me figure out </think> the note.\n</think>\nDone.'), 'Done.');
    expect(answer('<think>Only reasoning.</think>\n'), isNull);
    expect(answer('No tags here.'), 'No tags here.');
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
    // Small enough to stay on a laptop GPU, and no long hidden thinking (#326).
    expect(body['options'], {'num_ctx': 16384, 'num_predict': maxReplyTokens});
    expect(body['think'], isFalse);
    expect((body['messages']! as List).first, {'role': 'system', 'content': 'be brief'});
    expect(((body['tools']! as List).first as Map)['function'], containsPair('name', 'read_note'));
    expect(call['timeout'], const Duration(seconds: 180));
    await provider.turn('', hi, []);
    final second = api.last['body']! as Map<String, Object?>;
    expect(second.containsKey('tools'), isFalse);
    expect(second['messages'], hi);
  });

  test(
    'a set temperature goes with the options: 0 decodes greedily, for a steady eval (#597)',
    () async {
      final api = Api()
        ..answers.add({
          'message': {'content': 'ok'},
        });
      final provider = OllamaProvider(
        'm',
        host: 'http://box:1',
        transport: api.call,
        temperature: 0,
      );
      await provider.turn('', [
        {'role': 'user', 'content': 'hi'},
      ], []);
      expect((api.last['body']! as Map)['options'], {
        'num_ctx': 16384,
        'num_predict': maxReplyTokens,
        'temperature': 0,
      });
    },
  );

  test('usage: the prompt and answer token counts Ollama reports', () {
    final used = fromOllama({
      'message': {'role': 'assistant', 'content': 'hi'},
      'prompt_eval_count': 26,
      'eval_count': 290,
    }).usage!;
    expect((used.input, used.output), (26, 290));
    expect(
      fromOllama({
        'message': {'role': 'assistant', 'content': 'hi'},
      }).usage,
      isNull,
    );
  });

  group('a model stuck repeating itself (#908)', () {
    /// Ollama for a model that never ends its reply: it stops only at the
    /// request's num_predict, as Ollama does, and says so in done_reason.
    Future<Object?> runaway(
      String method,
      String url, {
      Map<String, String> headers = const {},
      Object? body,
      required Duration timeout,
    }) async {
      final options = (body! as Map)['options'] as Map;
      final cap = options['num_predict'] as int?;
      if (cap == null) throw StateError('no cap: this reply would never end');
      return {
        'message': {
          'content': List.filled(cap, 'hatırlatma').join(' '),
          'tool_calls': [
            {
              'function': {
                'name': 'add_note',
                'arguments': {'text': 'cut'},
              },
            },
          ],
        },
        'done_reason': 'length',
        'eval_count': cap,
      };
    }

    test('stops at the cap and fails the turn instead of keeping the text', () async {
      final provider = OllamaProvider('v10', host: 'http://box:1', transport: runaway);
      await expectLater(
        provider.turn(
          '',
          [
            {'role': 'user', 'content': 'remind me'},
          ],
          [tool],
        ),
        throwsA(isA<ReplyTooLong>()),
      );
    });

    test('a reply that ends on its own is kept', () {
      final done = fromOllama({
        'message': {'content': 'Saved.'},
        'done_reason': 'stop',
      });
      expect(done.content, [
        {'type': 'text', 'text': 'Saved.'},
      ]);
    });
  });
}
