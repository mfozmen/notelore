/// The runtime implementation for a provider of the catalogue.
library;

import 'anthropic.dart';
import 'base.dart';
import 'chatgpt.dart';
import 'gemini.dart';
import 'http.dart';
import 'ollama.dart';
import 'openai.dart';

LlmProvider createProvider(
  ProviderSpec spec,
  String? apiKey, {
  String? model,
  Transport transport = defaultTransport,
  BearerToken? planToken,
}) {
  final chosen = model ?? spec.defaultModel;
  return switch (spec.name) {
    'chatgpt' => ChatGptProvider(chosen, planToken!),
    'anthropic' => AnthropicProvider(apiKey ?? '', chosen, transport: transport),
    'openai' => OpenAIProvider(apiKey ?? '', chosen, transport: transport),
    'gemini' => GeminiProvider(apiKey ?? '', chosen, transport: transport),
    _ => OllamaProvider(chosen, transport: transport),
  };
}
