/// The runtime implementation for a provider of the catalogue.
library;

import 'package:http/http.dart' as http;

import 'anthropic.dart';
import 'base.dart';
import 'chatgpt.dart';
import 'deepseek.dart';
import 'gemini.dart';
import 'http.dart';
import 'ollama.dart';

LlmProvider createProvider(
  ProviderSpec spec,
  String? apiKey, {
  String? model,
  Transport transport = defaultTransport,
  BearerToken? planToken,
  http.Client? client,
  bool webSearch = false,
}) {
  final chosen = model ?? spec.defaultModel;
  return switch (spec.name) {
    'chatgpt' => ChatGptProvider(chosen, planToken!, client: client, webSearch: webSearch),
    'anthropic' => AnthropicProvider(
      apiKey ?? '',
      chosen,
      transport: transport,
      webSearch: webSearch,
    ),
    // The key is a token that never needs a refresh.
    'openai' => ChatGptProvider(
      chosen,
      ({refresh = false}) async => apiKey ?? '',
      client: client,
      namespace: null,
      webSearch: webSearch,
    ),
    'gemini' => GeminiProvider(apiKey ?? '', chosen, transport: transport),
    'deepseek' => DeepSeekProvider(apiKey ?? '', chosen, transport: transport),
    _ => OllamaProvider(chosen, transport: transport),
  };
}
