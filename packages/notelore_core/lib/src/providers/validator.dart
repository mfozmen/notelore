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
  'anthropic': ('$anthropicModels?limit=1000', anthropicHeaders, 'Anthropic'),
  'openai': (openAIModels, openAIHeaders, 'OpenAI'),
  'gemini': ('$geminiModels?pageSize=1000', geminiHeaders, 'Google'),
};

// OpenAI lists every model the key can use; these are not chat models.
final _notChat = RegExp('audio|realtime|transcribe|tts|image|search|instruct');

/// The chat models in a provider's model listing; an odd answer gives none.
List<String> chatModels(String provider, Object? answer) {
  if (answer is! Map) return [];
  final items = answer[provider == 'gemini' || provider == 'ollama' ? 'models' : 'data'];
  if (items is! List) return [];
  final listed = items.whereType<Map<Object?, Object?>>();
  return switch (provider) {
    'gemini' => [
      for (final m in listed)
        if ((m['supportedGenerationMethods'] as List?)?.contains('generateContent') ?? false)
          '${m['name']}'.replaceFirst('models/', ''),
    ],
    'ollama' => [for (final m in listed) '${m['name']}'],
    'openai' => [
      for (final m in listed)
        if (RegExp(r'^(gpt-|o\d)').hasMatch('${m['id']}') && !_notChat.hasMatch('${m['id']}'))
          '${m['id']}',
    ]..sort((a, b) => b.compareTo(a)),
    _ => [for (final m in listed) '${m['id']}'],
  };
}

/// Checks [apiKey] and returns the chat models it can use (newest first where the
/// provider says so). Throws [KeyValidationError] or [TransientValidationError].
Future<List<String>> validateKey(
  ProviderSpec spec,
  String apiKey, {
  Transport transport = defaultTransport,
  String? ollamaHost,
}) async {
  if (spec.name == 'ollama') return _checkOllama(transport, ollamaHost ?? ollama.ollamaHost());
  final (url, headers, vendor) = _listings[spec.name]!;
  try {
    return chatModels(
      spec.name,
      await transport('GET', url, headers: headers(apiKey), timeout: _timeout),
    );
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

/// Key-less: the check only asks whether the local daemon answers, and which
/// models it has pulled.
Future<List<String>> _checkOllama(Transport transport, String host) async {
  try {
    return chatModels('ollama', await transport('GET', '$host/api/tags', timeout: _timeout));
  } on Exception catch (error) {
    throw TransientValidationError(
      'Ollama is not reachable on $host; start the daemon and retry. ($error)',
    );
  }
}
