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
      'https://api.anthropic.com/v1/models',
      {'x-api-key': 'key', 'anthropic-version': '2023-06-01'},
    ),
    'openai': ('https://api.openai.com/v1/models', {'Authorization': 'Bearer key'}),
    'gemini': (
      'https://generativelanguage.googleapis.com/v1beta/models',
      {'x-goog-api-key': 'key'},
    ),
  };
  for (final MapEntry(key: name, value: (url, headers)) in listings.entries) {
    test('a good $name key lists the models and spends no tokens', () async {
      api.answers.add({'data': <Object?>[]});
      await validateKey(findProvider(name), 'key', transport: api.call);
      expect(api.last, {
        'method': 'GET',
        'url': url,
        'headers': headers,
        'body': null,
        'timeout': const Duration(seconds: 5),
      });
    });
  }

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
