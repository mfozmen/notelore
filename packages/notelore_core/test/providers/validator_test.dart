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

  test('Ollama only needs a reachable daemon', () async {
    api.answers.add({'models': <Object?>[]});
    await validateKey(findProvider('ollama'), '', transport: api.call, ollamaHost: 'http://box:1');
    expect(api.last['url'], 'http://box:1/api/tags');
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
}
