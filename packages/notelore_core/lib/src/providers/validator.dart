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
    'gemini' => _geminiChat(listed),
    'ollama' => [for (final m in listed) '${m['name']}'],
    'openai' => _openAIChat(listed),
    _ => [for (final m in listed) '${m['id']}'],
  };
}

/// Gemini models that can chat (generateContent), without the `models/` prefix.
List<String> _geminiChat(Iterable<Map<Object?, Object?>> listed) => [
  for (final m in listed)
    if ((m['supportedGenerationMethods'] as List?)?.contains('generateContent') ?? false)
      '${m['name']}'.replaceFirst('models/', ''),
];

/// OpenAI's GPT and o-series chat models, newest name first; the key also
/// lists audio, image and search models.
List<String> _openAIChat(Iterable<Map<Object?, Object?>> listed) => [
  for (final m in listed)
    if (RegExp(r'^(gpt-|o\d)').hasMatch('${m['id']}') && !_notChat.hasMatch('${m['id']}'))
      '${m['id']}',
]..sort((a, b) => b.compareTo(a));

/// Cheapest first. Listings carry no prices, so the family name decides.
final _tiers = [
  for (final family in ['nano', 'lite', 'mini|flash|haiku']) RegExp('(^|-)($family)(-|\$)'),
];

// Previews, experiments and pinned versions (dated, -001): only when nothing else is left.
final _pinned = RegExp(r'preview|exp|latest|-\d{4}-\d{2}-\d{2}$|-\d{8}$|-\d{3}$');
final _number = RegExp(r'\d+(\.\d+)?');

/// The first version number in a model id (`gpt-5.1` 5.1, `o4-mini` 4), 0 without one.
/// shortcut: only the first number counts (`claude-sonnet-4-5` and `-4` tie); fine
/// for today's ids, revisit if a provider puts a date or build number first.
double _version(String id) => double.parse(_number.firstMatch(id)?[0] ?? '0');

/// The price tier of a model id: 0 (nano) is the cheapest.
int _tier(String id) {
  final found = _tiers.indexWhere((t) => t.hasMatch(id));
  return found < 0 ? _tiers.length : found;
}

/// [models] without previews and pinned versions (unless that leaves none),
/// newest first: Anthropic already lists them so, the others by version number.
List<String> _newestFirst(String provider, List<String> models) {
  final plain = models.where((m) => !_pinned.hasMatch(m)).toList();
  final pool = plain.isEmpty ? [...models] : plain;
  if (provider != 'anthropic') {
    pool.sort((a, b) {
      final byVersion = _version(b).compareTo(_version(a));
      return byVersion != 0 ? byVersion : b.compareTo(a);
    });
  }
  return pool;
}

/// Only the current versions of what a provider lists: the newest of each model
/// family (the id without its numbers), minus families whose line (the id up
/// to its first number) has a newer generation that costs no more: a new top
/// model never hides the cheaper ones before it. A note-taking app needs no
/// archive of old models. Ollama's list is untouched.
List<String> currentModels(String provider, List<String> models) {
  if (provider == 'ollama') return models;
  final families = <String>{};
  final newest = [
    for (final m in _newestFirst(provider, models))
      if (families.add(m.replaceAll(_number, '#'))) m,
  ];
  String line(String id) => id.substring(0, _number.firstMatch(id)?.start ?? id.length);
  int generation(String id) => _version(id).floor();
  // Outdated: its line has a newer generation that costs no more.
  bool outdated(String m) => newest.any(
    (k) => line(k) == line(m) && generation(k) > generation(m) && _tier(k) <= _tier(m),
  );
  return [
    for (final m in newest)
      if (!outdated(m)) m,
  ];
}

/// Ollama runs, but has no model to talk with: the person pulls one first.
class NoLocalModel implements Exception {
  const NoLocalModel();
}

/// The installed Ollama model to start on (#471): Notelore's own fine-tune (the
/// newest), else Qwen3 4B, else any Qwen3, else the first listed; null when
/// none is installed. Never a fixed name Ollama may not have.
String? ollamaStartModel(List<String> models) {
  final tuned = models.where((m) => m.startsWith('notelore-')).toList()..sort(_byVersion);
  if (tuned.isNotEmpty) return tuned.last;
  for (final family in ['qwen3:4b', 'qwen3']) {
    final hit = models.where((m) => m.startsWith(family)).toList()..sort();
    if (hit.isNotEmpty) return hit.first;
  }
  return models.firstOrNull;
}

/// By the fine-tune's version ("-v10" after "-v9"), then by name.
int _byVersion(String a, String b) {
  int? version(String m) => switch (RegExp(r'-v(\d+)').firstMatch(m)) {
    final match? => int.parse(match[1]!),
    null => null,
  };
  final (va, vb) = (version(a), version(b));
  if (va != null && vb != null && va != vb) return va.compareTo(vb);
  return a.compareTo(b);
}

/// The cheapest of the [models] a provider listed, newest first within a tier;
/// null when none is listed.
String? cheapestModel(String provider, List<String> models) {
  String? best;
  for (final m in _newestFirst(provider, models)) {
    if (best == null || _tier(m) < _tier(best)) best = m;
  }
  return best;
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
  final List<String> models;
  try {
    models = chatModels('ollama', await transport('GET', '$host/api/tags', timeout: _timeout));
  } on Exception catch (error) {
    throw TransientValidationError(
      'Ollama is not reachable on $host; start the daemon and retry. ($error)',
    );
  }
  if (models.isEmpty) {
    throw const TransientValidationError(
      'Ollama has no model yet; pull one first, for example: ollama pull qwen3:4b',
    );
  }
  return models;
}
