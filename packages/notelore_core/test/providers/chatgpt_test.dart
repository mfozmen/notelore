import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notelore_core/src/oauth.dart';
import 'package:notelore_core/src/providers/base.dart';
import 'package:notelore_core/src/providers/chatgpt.dart';
import 'package:notelore_core/src/providers/http.dart';
import 'package:test/test.dart';

import 'base_test.dart' show conversation, tool;

/// A server-sent event stream as the Responses API sends it.
String sse(List<Map<String, Object?>> events) =>
    [for (final e in events) 'event: ${e['type']}\ndata: ${jsonEncode(e)}\n\n'].join();

Map<String, Object?> completed(List<Object?> output, {String status = 'completed'}) => {
  'type': status == 'completed' ? 'response.completed' : 'response.incomplete',
  'response': {
    'status': status,
    'output': output,
    if (status != 'completed') 'incomplete_details': {'reason': 'max_output_tokens'},
  },
};

/// The Responses API, in memory: answers with [answers] in order, records requests.
class FakeResponses {
  FakeResponses(this.answers);

  final List<http.Response> answers;
  final requests = <http.Request>[];

  late final client = MockClient((request) async {
    requests.add(request);
    return answers.removeAt(0);
  });

  Map<String, Object?> body(int i) => (jsonDecode(requests[i].body) as Map).cast();
}

http.Response stream(List<Map<String, Object?>> events) =>
    http.Response(sse(events), 200, headers: {'content-type': 'text/event-stream; charset=utf-8'});

void main() {
  late List<bool> refreshes;
  setUp(() => refreshes = []);

  Future<String> token({bool refresh = false}) async {
    refreshes.add(refresh);
    return refresh ? 'fresh' : 'stale';
  }

  ChatGptProvider provider(FakeResponses api) =>
      ChatGptProvider('gpt-x', token, client: api.client);

  test('a turn: Responses API, streaming, nothing stored, tools in a namespace', () async {
    final api = FakeResponses([
      stream([
        {'type': 'response.created'},
        {'type': 'response.output_text.delta', 'delta': 'Mer'},
        completed([
          {'type': 'reasoning', 'summary': <Object?>[]},
          {
            'type': 'message',
            'role': 'assistant',
            'content': [
              {'type': 'output_text', 'text': 'Merhaba!'},
            ],
          },
        ]),
      ]),
    ]);
    final response = await provider(api).turn(
      'be brief',
      [
        {'role': 'user', 'content': 'selam'},
      ],
      [tool],
    );
    expect(response.content, [
      {'type': 'text', 'text': 'Merhaba!'},
    ]);
    expect(response.stopReason, 'end_turn');
    final request = api.requests.single;
    expect(request.url.toString(), 'https://api.openai.com/v1/responses');
    expect(request.headers['Authorization'], 'Bearer stale');
    expect(api.body(0), {
      'model': 'gpt-x',
      'instructions': 'be brief', // never a system-role item
      'input': [
        {'role': 'user', 'content': 'selam'},
      ],
      'tools': [
        {
          'type': 'namespace',
          'name': 'notelore',
          'description': "Notelore's note tools.",
          'tools': [
            {
              'type': 'function',
              'name': 'read_note',
              'description': 'Read a note',
              'parameters': tool.inputSchema,
            },
          ],
        },
      ],
      'store': false,
      'stream': true,
    });
  });

  test('without a namespace (an API key): plain tools, plain calls in the history', () async {
    final api = FakeResponses([
      stream([completed([])]),
    ]);
    await ChatGptProvider('gpt-x', token, client: api.client, namespace: null).turn(
      '',
      [
        {
          'role': 'assistant',
          'content': [
            {'type': 'tool_use', 'id': 'c', 'name': 'read_note', 'input': <String, Object?>{}},
          ],
        },
      ],
      [tool],
    );
    expect(api.body(0)['tools'], [
      {
        'type': 'function',
        'name': 'read_note',
        'description': 'Read a note',
        'parameters': tool.inputSchema,
      },
    ]);
    expect(api.body(0)['input'], [
      {'type': 'function_call', 'call_id': 'c', 'name': 'read_note', 'arguments': '{}'},
    ]);
  });

  test('web search: the hosted tool goes along; its calls in the output are skipped', () async {
    final api = FakeResponses([
      stream([
        completed([
          {'type': 'web_search_call', 'id': 'ws1', 'status': 'completed'},
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': 'Can Dündar', 'annotations': <Object?>[]},
            ],
          },
        ]),
      ]),
      stream([completed([])]),
    ]);
    final response = await ChatGptProvider(
      'gpt-x',
      token,
      client: api.client,
      webSearch: true,
    ).turn('', [], [tool]);
    expect(response.content, [
      {'type': 'text', 'text': 'Can Dündar'},
    ]);
    expect((api.body(0)['tools']! as List).last, {'type': 'web_search'});
    // Search alone, without note tools, still sends the tools list.
    await ChatGptProvider('gpt-x', token, client: api.client, webSearch: true).turn('', [], []);
    expect(api.body(1)['tools'], [
      {'type': 'web_search'},
    ]);
  });

  test(
    'a route that refuses the search tool: the turn goes again without it, and stays so',
    () async {
      final api = FakeResponses([
        http.Response(
          '{"error": {"message": "Tool type web_search is not supported for this request"}}',
          400,
        ),
        stream([completed([])]),
        stream([completed([])]),
      ]);
      final provider = ChatGptProvider('gpt-x', token, client: api.client, webSearch: true);
      await provider.turn('', [], [tool]);
      await provider.turn('', [], [tool]);
      expect((api.body(0)['tools']! as List).last, {'type': 'web_search'});
      expect(api.body(1)['tools'], isNot(contains({'type': 'web_search'})));
      expect(api.body(2)['tools'], isNot(contains({'type': 'web_search'})));
      // Any other 400 is still an error.
      await expectLater(
        ChatGptProvider(
          'gpt-x',
          token,
          client: FakeResponses([http.Response('{"error": {"message": "bad input"}}', 400)]).client,
          webSearch: true,
        ).turn('', [], [tool]),
        throwsA(isA<HttpError>()),
      );
    },
  );

  test('tool calls come back as tool_use blocks', () async {
    final api = FakeResponses([
      stream([
        completed([
          {
            'type': 'function_call',
            'call_id': 'call_1',
            'namespace': 'notelore',
            'name': 'read_note',
            'arguments': '{"slug": "x"}',
          },
        ]),
      ]),
    ]);
    final response = await provider(api).turn('', [
      {'role': 'user', 'content': 'hi'},
    ], []);
    expect(response.stopReason, 'tool_use');
    expect(response.content, [
      {
        'type': 'tool_use',
        'id': 'call_1',
        'name': 'read_note',
        'input': {'slug': 'x'},
      },
    ]);
    final body = api.body(0);
    expect(body.containsKey('instructions'), isFalse);
    expect(body.containsKey('tools'), isFalse);
  });

  test('the history goes into input: messages, calls and their outputs', () {
    expect(toResponsesInput(conversation), [
      {'role': 'user', 'content': 'hi'},
      {'role': 'assistant', 'content': 'checking'},
      {
        'type': 'function_call',
        'call_id': 't1',
        'namespace': 'notelore',
        'name': 'read_note',
        'arguments': '{"slug":"x"}',
      },
      {
        'type': 'function_call',
        'call_id': '',
        'namespace': 'notelore',
        'name': 'no-id-is-skipped',
        'arguments': '{}',
      },
      {'type': 'function_call_output', 'call_id': 't1', 'output': 'ok'},
    ]);
    // A user turn with an image: one message of text and image parts (#278).
    expect(
      toResponsesInput([
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'look'},
            imageBlock('image/png', [1, 2, 3]),
          ],
        },
      ]),
      [
        {
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': 'look'},
            {'type': 'input_image', 'image_url': 'data:image/png;base64,AQID'},
          ],
        },
      ],
    );
    // An assistant turn with only tool calls has no empty text message.
    expect(
      toResponsesInput([
        {
          'role': 'assistant',
          'content': [
            {'type': 'tool_use', 'id': 'c', 'name': 'n', 'input': null},
          ],
        },
      ]),
      [
        {
          'type': 'function_call',
          'call_id': 'c',
          'namespace': 'notelore',
          'name': 'n',
          'arguments': '{}',
        },
      ],
    );
  });

  test('items streamed one by one count when the final output is empty', () async {
    // The plan route sends each item as it finishes and an empty final output.
    final api = FakeResponses([
      stream([
        {
          'type': 'response.output_item.done',
          'item': {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': 'Not aldım.'},
            ],
          },
        },
        {
          'type': 'response.output_item.done',
          'item': {
            'type': 'function_call',
            'call_id': 'call_1',
            'name': 'read_note',
            'arguments': '{}',
          },
        },
        completed([]),
      ]),
    ]);
    final response = await provider(api).turn('', [], []);
    expect(response.content, [
      {'type': 'text', 'text': 'Not aldım.'},
      {'type': 'tool_use', 'id': 'call_1', 'name': 'read_note', 'input': <String, Object?>{}},
    ]);
    expect(response.stopReason, 'tool_use');
  });

  test('lines that are not JSON events are skipped', () async {
    final api = FakeResponses([
      http.Response(': keep-alive comment\ndata: [DONE]\n\n${sse([completed([])])}', 200),
    ]);
    expect((await provider(api).turn('', [], [])).content, isEmpty);
  });

  test('an answer cut short says so', () async {
    final api = FakeResponses([
      stream([
        completed([
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': 'partial'},
            ],
          },
        ], status: 'incomplete'),
      ]),
    ]);
    final response = await provider(api).turn('', [], []);
    expect(response.content.last, {
      'type': 'text',
      'text': '[The model stopped early: max_output_tokens.]',
    });
  });

  test('an expired token is refreshed once', () async {
    final api = FakeResponses([
      http.Response('{"error": {"message": "expired"}}', 401),
      stream([completed([])]),
    ]);
    await provider(api).turn('', [], []);
    expect(refreshes, [false, true]);
    expect(api.requests.last.headers['Authorization'], 'Bearer fresh');
  });

  test('a used-up plan points to the usage settings', () async {
    for (final answer in [
      http.Response(
        '{"error": {"code": "subscription_sharing_usage_limit_exceeded", "message": "limit"}}',
        429,
      ),
      stream([
        {
          'type': 'response.failed',
          'response': {
            'error': {'code': 'subscription_sharing_usage_unavailable', 'message': 'no'},
          },
        },
      ]),
    ]) {
      await expectLater(
        provider(FakeResponses([answer])).turn('', [], []),
        throwsA(isA<PlanLimitReached>().having((e) => '$e', 'message', contains(chatGptUsageUrl))),
      );
    }
  });

  test('other failures: a revoked user, an API error, a broken stream, no network', () async {
    await expectLater(
      provider(
        FakeResponses([
          http.Response('{"error": {"code": "subscription_sharing_invalid_user"}}', 401),
          http.Response('{"error": {"code": "subscription_sharing_invalid_user"}}', 401),
        ]),
      ).turn('', [], []),
      throwsA(isA<NotSignedIn>()),
    );
    await expectLater(
      provider(
        FakeResponses([
          http.Response(
            '{"error": {"code": "subscription_sharing_unsupported_capability", "message": "no tools"}}',
            400,
          ),
        ]),
      ).turn('', [], []),
      throwsA(isA<HttpError>().having((e) => e.message, 'message', 'no tools')),
    );
    await expectLater(
      provider(
        FakeResponses([
          stream([
            {
              'type': 'response.failed',
              'response': {
                'error': {'code': 'server_error', 'message': 'overloaded'},
              },
            },
          ]),
        ]),
      ).turn('', [], []),
      throwsA(isA<HttpError>().having((e) => e.message, 'message', 'overloaded')),
    );
    await expectLater(
      provider(
        FakeResponses([
          stream([
            {'type': 'response.output_text.delta', 'delta': 'half'},
          ]),
        ]),
      ).turn('', [], []),
      throwsA(isA<NetworkError>()),
    );
    final offline = ChatGptProvider(
      'gpt-x',
      token,
      client: MockClient((_) async => throw http.ClientException('no route')),
    );
    await expectLater(offline.turn('', [], []), throwsA(isA<NetworkError>()));
    final slow = ChatGptProvider(
      'gpt-x',
      token,
      client: MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 10),
    );
    await expectLater(slow.turn('', [], []), throwsA(isA<NetworkError>()));
  });

  /// A stream that sends one event and then loses the connection.
  Stream<List<int>> brokenOff() async* {
    yield utf8.encode('data: {"type": "response.created"}\n');
    throw http.ClientException('connection reset');
  }

  test('a non-JSON error page and a stream that breaks off', () async {
    await expectLater(
      provider(FakeResponses([http.Response('Bad Gateway', 502)])).turn('', [], []),
      throwsA(
        isA<HttpError>()
            .having((e) => e.status, 'status', 502)
            .having((e) => e.message, 'message', 'Bad Gateway'),
      ),
    );
    final dropped = ChatGptProvider(
      'gpt-x',
      token,
      client: MockClient.streaming(
        (request, body) async => http.StreamedResponse(brokenOff(), 200),
      ),
    );
    await expectLater(
      dropped.turn('', [], []),
      throwsA(isA<NetworkError>().having((e) => e.message, 'message', 'connection reset')),
    );
  });

  test('the models the plan can use', () async {
    final api = FakeResponses([
      http.Response(
        jsonEncode({
          'models': [
            {'slug': 'gpt-x', 'display_name': 'GPT X', 'visibility': 'list'},
            {'slug': 'gpt-hidden', 'visibility': 'hidden'},
            {'slug': 'gpt-y', 'visibility': 'list'},
          ],
        }),
        200,
      ),
    ]);
    expect(await listChatGptModels(token, client: api.client), ['gpt-x', 'gpt-y']);
    expect(api.requests.single.url.toString(), 'https://api.openai.com/v1/models');
    expect(api.requests.single.method, 'GET');
    final odd = FakeResponses([http.Response('{"data": []}', 200)]);
    expect(await listChatGptModels(token, client: odd.client), isEmpty);
  });

  test('the model list with its own client: closed again, even when signed out', () async {
    Future<String> signedOut({bool refresh = false}) async => throw const NotSignedIn();
    await expectLater(listChatGptModels(signedOut), throwsA(isA<NotSignedIn>()));
  });

  test('the spec and the default client', () {
    final spec = findProvider('chatgpt');
    expect(spec.requiresApiKey, isFalse);
    expect(spec.cost, contains('ChatGPT Plus or Pro plan'));
    expect(ChatGptProvider('m', token).model, 'm');
    expect('${const PlanLimitReached()}', contains(chatGptUsageUrl));
  });

  test('usage: the final response reports the tokens; none when it does not', () {
    final used = fromResponse({
      'output': <Object?>[],
      'usage': {'input_tokens': 300, 'output_tokens': 25, 'total_tokens': 325},
    }).usage!;
    expect((used.input, used.output), (300, 25));
    expect(fromResponse({'output': <Object?>[]}).usage, isNull);
  });
}
