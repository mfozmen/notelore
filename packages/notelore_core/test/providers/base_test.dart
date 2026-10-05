import 'package:notelore_core/src/providers/anthropic.dart';
import 'package:notelore_core/src/providers/base.dart';
import 'package:notelore_core/src/providers/gemini.dart';
import 'package:notelore_core/src/providers/ollama.dart';
import 'package:notelore_core/src/providers/openai.dart';
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
    expect(providerSpecs.map((s) => s.name), ['anthropic', 'openai', 'gemini', 'ollama']);
    expect(findProvider('anthropic').keySteps, isNotEmpty);
    expect(findProvider('ollama').requiresApiKey, isFalse);
    expect(
      () => findProvider('bard'),
      throwsA(isA<ArgumentError>().having((e) => '$e', 'message', contains('unknown provider'))),
    );
  });

  final kinds = {
    'anthropic': isA<AnthropicProvider>(),
    'openai': isA<OpenAIProvider>(),
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
    final (:texts, :uses, :results) = splitBlocks(conversation[1]['content']);
    expect(texts, ['checking']);
    expect(uses.map((u) => u['name']), ['read_note', 'no-id-is-skipped']);
    expect(results, isEmpty);
    expect(splitBlocks(conversation[2]['content']).results.single['tool_use_id'], 't1');
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
