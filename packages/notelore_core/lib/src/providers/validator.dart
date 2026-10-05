/// Verifies a freshly entered API key by listing the provider's models.
///
/// Listing models is free (no tokens) and needs a valid key. Two outcomes the UI
/// handles differently:
///
/// - [KeyValidationError]: the provider rejected the key. Ask again, and forget a
///   saved key.
/// - [TransientValidationError]: the call failed for another reason (rate limit,
///   5xx, network, daemon down). Keep a saved key; silently wiping it over a flaky
///   network would be hostile.
library;

import 'anthropic.dart';
import 'base.dart';
import 'gemini.dart';
import 'http.dart';
import 'ollama.dart' as ollama;
import 'openai.dart';

const _timeout = Duration(seconds: 5); // a key with working DNS and TLS answers well under a second

/// The provider explicitly rejected the key.
class KeyValidationError implements Exception {
  const KeyValidationError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The check failed, but the key is not the reason.
class TransientValidationError implements Exception {
  const TransientValidationError(this.message);

  final String message;

  @override
  String toString() => message;
}

final _listings = <String, (String, Map<String, String> Function(String), String)>{
  'anthropic': (anthropicModels, anthropicHeaders, 'Anthropic'),
  'openai': (openAIModels, openAIHeaders, 'OpenAI'),
  'gemini': (geminiModels, geminiHeaders, 'Google'),
};

Future<void> validateKey(
  ProviderSpec spec,
  String apiKey, {
  Transport transport = defaultTransport,
  String? ollamaHost,
}) async {
  if (spec.name == 'ollama') return _checkOllama(transport, ollamaHost ?? ollama.ollamaHost());
  final (url, headers, vendor) = _listings[spec.name]!;
  try {
    await transport('GET', url, headers: headers(apiKey), timeout: _timeout);
  } on HttpError catch (error) {
    // Gemini answers a bad key with 400 "API key not valid" rather than 401/403.
    if (error.status == 401 ||
        error.status == 403 ||
        (error.status == 400 && error.message.toLowerCase().contains('api key'))) {
      throw KeyValidationError('$vendor rejected the key: ${error.message}');
    }
    throw TransientValidationError('$vendor call failed: $error');
  } on NetworkError catch (error) {
    throw TransientValidationError('$vendor is not reachable: ${error.message}');
  }
}

/// Key-less: the check only asks whether the local daemon answers.
Future<void> _checkOllama(Transport transport, String host) async {
  try {
    await transport('GET', '$host/api/tags', timeout: _timeout);
  } on Exception catch (error) {
    throw TransientValidationError(
      'Ollama is not reachable on $host; start the daemon and retry. ($error)',
    );
  }
}
