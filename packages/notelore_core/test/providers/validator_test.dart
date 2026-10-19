import 'package:notelore_core/src/providers/base.dart';
import 'package:notelore_core/src/providers/http.dart';
import 'package:notelore_core/src/providers/validator.dart';
import 'package:test/test.dart';

import 'fake_api.dart';

void main() {
  late Api api;
  setUp(() => api = Api());

  final listings = {
    'anthropic': (
      'https://api.anthropic.com/v1/models?limit=1000',
      {'x-api-key': 'key', 'anthropic-version': '2023-06-01'},
    ),
    'openai': ('https://api.openai.com/v1/models', {'Authorization': 'Bearer key'}),
    'gemini': (
      'https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000',
      {'x-goog-api-key': 'key'},
    ),
  };
  for (final MapEntry(key: name, value: (url, headers)) in listings.entries) {
    test('a good $name key lists the models and spends no tokens', () async {
      api.answers.add({'data': <Object?>[]});
      expect(await validateKey(findProvider(name), 'key', transport: api.call), isEmpty);
      expect(api.last, {
        'method': 'GET',
        'url': url,
        'headers': headers,
        'body': null,
        'timeout': const Duration(seconds: 5),
      });
    });
  }

  test('the chat models each provider lists', () async {
    api.answers.addAll([
      {
        'data': [
          {'id': 'claude-opus-5-5'},
          {'id': 'claude-sonnet-5-5'},
        ],
      },
      {
        'data': [
          {'id': 'gpt-4o-mini'},
          {'id': 'gpt-5'},
          {'id': 'o3'},
          {'id': 'gpt-4o-audio-preview'},
          {'id': 'gpt-4o-realtime-preview'},
          {'id': 'gpt-4o-mini-transcribe'},
          {'id': 'gpt-4o-mini-tts'},
          {'id': 'gpt-image-1'},
          {'id': 'gpt-4o-search-preview'},
          {'id': 'gpt-3.5-turbo-instruct'},
          {'id': 'text-embedding-3-small'},
          {'id': 'dall-e-3'},
          {'id': 'whisper-1'},
        ],
      },
      {
        'models': [
          {
            'name': 'models/gemini-2.5-pro',
            'supportedGenerationMethods': ['generateContent', 'countTokens'],
          },
          {
            'name': 'models/gemini-embedding-001',
            'supportedGenerationMethods': ['embedContent'],
          },
          {
            'name': 'models/imagen-4.0-generate-001',
            'supportedGenerationMethods': ['predict'],
          },
        ],
      },
      {
        'models': [
          {'name': 'llama3.2:latest'},
          {'name': 'qwen3:8b'},
        ],
      },
    ]);
    Future<List<String>> models(String name) =>
        validateKey(findProvider(name), 'key', transport: api.call, ollamaHost: 'http://box:1');
    // Newest first as Anthropic lists them; OpenAI has no order: reverse alphabetical.
    expect(await models('anthropic'), ['claude-opus-5-5', 'claude-sonnet-5-5']);
    expect(await models('openai'), ['o3', 'gpt-5', 'gpt-4o-mini']);
    expect(await models('gemini'), ['gemini-2.5-pro']);
    expect(await models('ollama'), ['llama3.2:latest', 'qwen3:8b']);
  });

  test('an odd listing gives no models rather than an error', () async {
    api.answers.addAll([
      null,
      'not a map',
      <String, Object?>{'data': 'nope'},
    ]);
    for (final _ in [1, 2, 3]) {
      expect(await validateKey(findProvider('anthropic'), 'key', transport: api.call), isEmpty);
    }
  });

  final failures = <(Exception, Matcher)>[
    (const HttpError(401, 'invalid x-api-key'), throwsA(isA<KeyValidationError>())),
    (const HttpError(403, 'permission denied'), throwsA(isA<KeyValidationError>())),
    (const HttpError(429, 'rate limited'), throwsA(isA<TransientValidationError>())),
    (const HttpError(500, 'overloaded'), throwsA(isA<TransientValidationError>())),
    (const NetworkError('no route to host'), throwsA(isA<TransientValidationError>())),
  ];
  for (final name in ['anthropic', 'openai', 'gemini']) {
    for (final (error, matcher) in failures) {
      test('$name: $error', () async {
        api.answers.add(error);
        await expectLater(validateKey(findProvider(name), 'key', transport: api.call), matcher);
      });
    }
  }

  test('Gemini reports a bad key as 400', () async {
    api.answers.add(const HttpError(400, 'API key not valid. Please pass a valid API key.'));
    await expectLater(
      validateKey(findProvider('gemini'), 'key', transport: api.call),
      throwsA(
        isA<KeyValidationError>().having(
          (e) => '$e',
          'message',
          contains('Google rejected the key'),
        ),
      ),
    );
    api.answers.add(const HttpError(400, 'Invalid JSON payload'));
    await expectLater(
      validateKey(findProvider('gemini'), 'key', transport: api.call),
      throwsA(isA<TransientValidationError>()),
    );
  });

  test('Ollama only needs a reachable daemon with a model pulled', () async {
    api.answers.add({
      'models': [
        {'name': 'qwen3:4b'},
      ],
    });
    await validateKey(findProvider('ollama'), '', transport: api.call, ollamaHost: 'http://box:1');
    expect(api.last['url'], 'http://box:1/api/tags');
    // It answers, but there is nothing to talk to yet: said, with the command (#360).
    api.answers.add({'models': <Object?>[]});
    await expectLater(
      validateKey(findProvider('ollama'), '', transport: api.call, ollamaHost: 'http://box:1'),
      throwsA(
        isA<TransientValidationError>().having(
          (e) => e.message,
          'message',
          contains('ollama pull'),
        ),
      ),
    );
    api.answers.add(const NetworkError('connection refused'));
    await expectLater(
      validateKey(findProvider('ollama'), '', transport: api.call, ollamaHost: 'http://box:1'),
      throwsA(
        isA<TransientValidationError>().having((e) => '$e', 'message', contains('http://box:1')),
      ),
    );
    api.answers.add(const HttpError(404, 'not found'));
    await expectLater(
      validateKey(findProvider('ollama'), '', transport: api.call),
      throwsA(isA<TransientValidationError>()),
    );
  });

  test('a captive portal is a transient failure', () async {
    api.answers.add(const HttpError(200, 'the answer was not JSON: <html>Sign in</html>'));
    await expectLater(
      validateKey(findProvider('openai'), 'key', transport: api.call),
      throwsA(isA<TransientValidationError>()),
    );
  });

  test('the cheapest listed model, by family name', () {
    // OpenAI: nano beats mini; the undated name beats its dated snapshot.
    expect(
      cheapestModel('openai', [
        'o4-mini',
        'gpt-5',
        'gpt-5-nano-2025-08-07',
        'gpt-5-nano',
        'gpt-4.1-nano',
        'gpt-4o-mini',
      ]),
      'gpt-5-nano',
    );
    // Gemini: flash-lite beats flash and pro; newest wins; previews only as a last resort.
    expect(
      cheapestModel('gemini', [
        'gemini-2.5-pro',
        'gemini-2.5-flash',
        'gemini-2.0-flash-lite-001',
        'gemini-2.5-flash-lite',
        'gemini-3.0-flash-lite-preview-09-25',
        'gemini-2.0-flash-lite',
      ]),
      'gemini-2.5-flash-lite',
    );
    expect(cheapestModel('gemini', ['gemini-9-flash-lite-preview']), 'gemini-9-flash-lite-preview');
    // Anthropic lists newest first, every id dated: the first haiku.
    expect(
      cheapestModel('anthropic', [
        'claude-opus-5-5-20260801',
        'claude-sonnet-5-5-20260801',
        'claude-haiku-5-0-20260601',
        'claude-haiku-4-5-20251001',
      ]),
      'claude-haiku-5-0-20260601',
    );
    // No known family: the first listed; nothing listed: none.
    expect(cheapestModel('anthropic', ['claude-x', 'claude-y']), 'claude-x');
    expect(cheapestModel('openai', []), isNull);
  });

  test('only the current versions stay in the list', () {
    expect(
      currentModels('openai', [
        'gpt-4o-mini',
        'gpt-4.1-nano',
        'gpt-5-nano-2025-08-07',
        'gpt-5-nano',
        'gpt-5-mini',
        'gpt-5',
        'gpt-5.1',
        'o3',
        'o4-mini',
      ]),
      ['gpt-5.1', 'gpt-5-nano', 'gpt-5-mini', 'o4-mini'],
    );
    // Versions compare as numbers: 10 is newer than 9.
    expect(currentModels('openai', ['gpt-9-mini', 'gpt-10-mini']), ['gpt-10-mini']);
    expect(
      currentModels('gemini', [
        'gemini-2.0-flash',
        'gemini-2.0-flash-lite-001',
        'gemini-2.5-flash',
        'gemini-2.5-flash-lite',
        'gemini-2.5-pro',
        'gemini-2.5-pro-preview-05-06',
        'gemini-exp-1206',
      ]),
      ['gemini-2.5-pro', 'gemini-2.5-flash-lite', 'gemini-2.5-flash'],
    );
    // Anthropic: dated ids only, newest first as listed.
    expect(
      currentModels('anthropic', [
        'claude-opus-5-5-20260801',
        'claude-sonnet-5-5-20260801',
        'claude-haiku-5-0-20260601',
        'claude-sonnet-4-5-20250929',
        'claude-haiku-4-5-20251001',
      ]),
      ['claude-opus-5-5-20260801', 'claude-sonnet-5-5-20260801', 'claude-haiku-5-0-20260601'],
    );
    // A new top model never pushes out the cheaper families of the generation
    // before it: generations compare within a price tier.
    expect(currentModels('gemini', ['gemini-3-pro', 'gemini-2.5-flash', 'gemini-2.5-flash-lite']), [
      'gemini-3-pro',
      'gemini-2.5-flash-lite',
      'gemini-2.5-flash',
    ]);
    expect(currentModels('openai', ['gpt-6', 'gpt-5-mini', 'gpt-5-nano', 'gpt-4o-mini']), [
      'gpt-6',
      'gpt-5-nano',
      'gpt-5-mini',
    ]);
    expect(cheapestModel('openai', ['gpt-6', 'gpt-5-mini', 'gpt-5-nano']), 'gpt-5-nano');
    // Previews only: they stay. Ollama: the machine's own models, untouched.
    expect(currentModels('gemini', ['gemini-9-flash-preview']), ['gemini-9-flash-preview']);
    expect(currentModels('ollama', ['llama3.2', 'llama3.1']), ['llama3.2', 'llama3.1']);
    expect(currentModels('openai', ['custom']), ['custom']);
  });

  test("Ollama starts on an installed model: Notelore's own, the newest, else Qwen3 (#471)", () {
    expect(
      ollamaStartModel([
        'llama3.2:3b',
        'qwen3:4b',
        'notelore-qwen3-4b-v2:latest',
        'notelore-qwen3-4b-v3:latest',
      ]),
      'notelore-qwen3-4b-v3:latest',
    );
    expect(ollamaStartModel(['llama3.2:3b', 'qwen3:8b', 'qwen3:4b-instruct']), 'qwen3:4b-instruct');
    expect(ollamaStartModel(['llama3.2:3b', 'qwen3:8b']), 'qwen3:8b');
    expect(ollamaStartModel(['llama3.2:3b', 'phi4-mini:latest']), 'llama3.2:3b');
    expect(ollamaStartModel([]), isNull);
    expect(const NoLocalModel(), isA<Exception>()); // what the app says to pull then
  });
}
