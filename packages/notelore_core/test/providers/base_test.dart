import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notelore_core/src/providers/anthropic.dart';
import 'package:notelore_core/src/providers/base.dart';
import 'package:notelore_core/src/providers/chatgpt.dart';
import 'package:notelore_core/src/providers/gemini.dart';
import 'package:notelore_core/src/providers/ollama.dart';
import 'package:notelore_core/src/providers/providers.dart';
import 'package:test/test.dart';

const conversation = <Message>[
  {'role': 'user', 'content': 'hi'},
  {
    'role': 'assistant',
    'content': [
      {'type': 'text', 'text': 'checking'},
      {
        'type': 'tool_use',
        'id': 't1',
        'name': 'read_note',
        'input': {'slug': 'x'},
      },
      {'type': 'tool_use', 'name': 'no-id-is-skipped', 'input': <String, Object?>{}},
    ],
  },
  {
    'role': 'user',
    'content': [
      {'type': 'tool_result', 'tool_use_id': 't1', 'content': 'ok'},
    ],
  },
];

const tool = Tool('read_note', 'Read a note', {
  'type': 'object',
  'properties': <String, Object?>{},
});

void main() {
  test('findProvider, known and unknown', () {
    expect(findProvider('anthropic').displayName, 'Claude (Anthropic)');
    expect(providerSpecs.map((s) => s.name), [
      'chatgpt',
      'anthropic',
      'openai',
      'gemini',
      'ollama',
    ]);
    expect(findProvider('anthropic').keySteps, isNotEmpty);
    // Who can look things up on the web (#96).
    expect(
      [
        for (final s in providerSpecs)
          if (s.webSearch) s.name,
      ],
      ['chatgpt', 'anthropic', 'openai'],
    );
    // Grouped by how they are paid for, in that order (#108).
    expect(
      {for (final s in providerSpecs) s.name: s.group},
      {
        'chatgpt': ProviderGroup.plan,
        'anthropic': ProviderGroup.apiKey,
        'openai': ProviderGroup.apiKey,
        'gemini': ProviderGroup.apiKey,
        'ollama': ProviderGroup.local,
      },
    );
    expect(ProviderGroup.values.map((g) => g.heading), [
      'Use your plan',
      'API key',
      'On this computer',
    ]);
    // What each one costs, so nobody is surprised by a bill (#95).
    expect(findProvider('anthropic').cost, contains('Pro or Max subscription cannot'));
    expect(findProvider('openai').cost, contains('per use'));
    expect(findProvider('gemini').cost, contains('without billing'));
    expect(findProvider('ollama').cost, startsWith('Free'));
    expect(findProvider('ollama').requiresApiKey, isFalse);
    expect(
      () => findProvider('bard'),
      throwsA(isA<ArgumentError>().having((e) => '$e', 'message', contains('unknown provider'))),
    );
  });

  final kinds = {
    'anthropic': isA<AnthropicProvider>(),
    'openai': isA<ChatGptProvider>(), // the Responses API, with the key as token
    'gemini': isA<GeminiProvider>(),
    'ollama': isA<OllamaProvider>(),
  };
  for (final MapEntry(key: name, value: matcher) in kinds.entries) {
    test('createProvider: $name', () {
      final provider = createProvider(findProvider(name), 'key');
      expect(provider, matcher);
      expect(provider.model, findProvider(name).defaultModel);
      expect(createProvider(findProvider(name), null, model: 'other').model, 'other');
    });
  }

  test('createProvider: an OpenAI key uses the Responses API, plain tools', () async {
    final requests = <http.Request>[];
    final provider = createProvider(
      findProvider('openai'),
      'sk-1',
      model: 'gpt-6.1-sol',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          'data: {"type":"response.completed","response":{"status":"completed","output":[]}}\n\n',
          200,
        );
      }),
    );
    await provider.turn(
      'sys',
      [
        {'role': 'user', 'content': 'hi'},
      ],
      [tool],
    );
    final request = requests.single;
    expect(request.url.toString(), 'https://api.openai.com/v1/responses');
    expect(request.headers['Authorization'], 'Bearer sk-1');
    final body = jsonDecode(request.body) as Map;
    expect(body['tools'], [
      {
        'type': 'function',
        'name': 'read_note',
        'description': 'Read a note',
        'parameters': tool.inputSchema,
      },
    ]);
  });

  test('createProvider passes web search to the providers that have it', () {
    Future<String> token({bool refresh = false}) async => 't';
    expect(
      (createProvider(
        findProvider('anthropic'),
        'k',
        webSearch: true,
      ) as AnthropicProvider).webSearch,
      isTrue,
    );
    expect(
      (createProvider(findProvider('openai'), 'k', webSearch: true) as ChatGptProvider).webSearch,
      isTrue,
    );
    expect(
      (createProvider(
        findProvider('chatgpt'),
        null,
        planToken: token,
        webSearch: true,
      ) as ChatGptProvider).webSearch,
      isTrue,
    );
    expect(
      (createProvider(findProvider('anthropic'), 'k') as AnthropicProvider).webSearch,
      isFalse,
    );
  });

  test('createProvider: chatgpt needs the plan token', () {
    Future<String> token({bool refresh = false}) async => 't';
    final provider = createProvider(findProvider('chatgpt'), null, model: 'm', planToken: token);
    expect(provider, isA<ChatGptProvider>());
    expect(provider.model, 'm');
  });

  test('toolUseNames skips id-less blocks', () {
    expect(toolUseNames(conversation), {'t1': 'read_note'});
  });

  test('splitBlocks', () {
    final plain = splitBlocks('plain');
    expect(
      [plain.texts, plain.uses, plain.results],
      [
        ['plain'],
        isEmpty,
        isEmpty,
      ],
    );
    final (:texts, :uses, :results, images: _) = splitBlocks(conversation[1]['content']);
    expect(texts, ['checking']);
    expect(uses.map((u) => u['name']), ['read_note', 'no-id-is-skipped']);
    expect(results, isEmpty);
    expect(splitBlocks(conversation[2]['content']).results.single['tool_use_id'], 't1');
  });

  test('images: told by their first bytes, sent as blocks, and who can see them (#278)', () {
    expect(imageType([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1]), 'image/png');
    expect(imageType([0xff, 0xd8, 0xff, 0xe0]), 'image/jpeg');
    expect(imageType('GIF89a'.codeUnits), 'image/gif');
    expect(imageType([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits]), 'image/webp');
    for (final other in [
      'hello'.codeUnits,
      [0x89],
      [...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WAVE'.codeUnits],
    ]) {
      expect(imageType(other), isNull, reason: '$other');
    }
    final block = imageBlock('image/png', [1, 2, 3]);
    expect(block, {
      'type': 'image',
      'source': {'type': 'base64', 'media_type': 'image/png', 'data': 'AQID'},
    });
    expect(
      splitBlocks([
        {'type': 'text', 'text': 'look'},
        block,
      ]).images,
      [block],
    );
    expect(splitBlocks('plain').images, isEmpty);
    // Ollama cannot tell whether a local model sees images: not offered there.
    expect(
      {
        for (final s in providerSpecs)
          if (s.images) s.name,
      },
      {'chatgpt', 'anthropic', 'openai', 'gemini'},
    );
  });

  final arguments = <Object?, Map<String, Object?>>{
    {'a': 1}: {'a': 1},
    '{"a": 1}': {'a': 1},
    '': {},
    null: {},
    'not json': {'__raw': 'not json'},
    '[1, 2]': {'__raw': '[1, 2]'},
  };
  for (final MapEntry(key: raw, value: expected) in arguments.entries) {
    test('parseArguments: $raw', () => expect(parseArguments(raw), expected));
  }

  test('a tool and a response are plain records', () {
    expect(tool.inputSchema['type'], 'object');
    const response = AgentResponse([], 'end_turn');
    expect(response.stopReason, 'end_turn');
  });
}
