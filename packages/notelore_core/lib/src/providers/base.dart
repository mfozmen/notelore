/// Provider catalogue and the one interface the agent loop talks to.
///
/// Ported from the Python reference (itself from littlepress-ai, same author,
/// MIT). Messages and content blocks use Anthropic's wire shape everywhere, as
/// plain JSON maps; the other providers translate at their boundary so the agent
/// never learns a second format.
library;

import 'dart:convert';
import 'dart:math';

/// A content block: {"type": "text" | "tool_use" | "tool_result", ...}.
typedef Block = Map<String, Object?>;

/// A message: `{"role": "user" | "assistant", "content": String | List<Block>}`.
typedef Message = Map<String, Object?>;

final class ProviderSpec {
  const ProviderSpec(
    this.name,
    this.displayName, {
    required this.requiresApiKey,
    required this.defaultModel,
    this.keyUrl,
    this.keySteps = const [],
  });

  final String name;
  final String displayName;
  final bool requiresApiKey;
  final String defaultModel;
  final String? keyUrl;
  final List<String> keySteps;
}

const providerSpecs = [
  ProviderSpec(
    'anthropic',
    'Claude (Anthropic)',
    requiresApiKey: true,
    defaultModel: 'claude-sonnet-5-5',
    keyUrl: 'https://console.anthropic.com/settings/keys',
    keySteps: [
      'Sign in to the Anthropic Console (a free account is enough).',
      'Click Create Key, give it a name such as notelore, and copy it.',
      'Paste the key below (it starts with sk-ant-).',
    ],
  ),
  ProviderSpec(
    'openai',
    'GPT (OpenAI)',
    requiresApiKey: true,
    defaultModel: 'gpt-4o-mini',
    keyUrl: 'https://platform.openai.com/api-keys',
    keySteps: [
      'Sign in to the OpenAI Platform.',
      'Click Create new secret key, give it a name, and copy it.',
      'Paste the key below (it starts with sk-).',
    ],
  ),
  ProviderSpec(
    'gemini',
    'Gemini (Google)',
    requiresApiKey: true,
    defaultModel: 'gemini-2.5-flash',
    keyUrl: 'https://aistudio.google.com/apikey',
    keySteps: [
      'Sign in to Google AI Studio.',
      'Click Create API key and copy it.',
      'Paste the key below.',
    ],
  ),
  ProviderSpec('ollama', 'Ollama (local)', requiresApiKey: false, defaultModel: 'llama3.2'),
];

ProviderSpec findProvider(String name) => providerSpecs.firstWhere(
  (spec) => spec.name == name,
  orElse: () => throw ArgumentError.value(
    name,
    'name',
    'unknown provider; known: ${providerSpecs.map((s) => s.name).join(', ')}',
  ),
);

final class Tool {
  const Tool(this.name, this.description, this.inputSchema);

  final String name;
  final String description;

  /// JSON Schema: type, properties, required, enum, items.
  final Map<String, Object?> inputSchema;
}

final class AgentResponse {
  const AgentResponse(this.content, this.stopReason);

  final List<Block> content;

  /// "end_turn" | "tool_use"
  final String stopReason;
}

abstract interface class LlmProvider {
  String get model;

  /// One agent step: the model's content blocks for the conversation so far.
  Future<AgentResponse> turn(String system, List<Message> messages, List<Tool> tools);
}

/// `tool_use` id -> tool name over the conversation.
///
/// A `tool_result` carries only the id; Gemini and Ollama correlate by name, so
/// their translators look it up here.
Map<String, String> toolUseNames(List<Message> messages) => {
  for (final message in messages)
    if (message['role'] == 'assistant' && message['content'] is List)
      for (final block in (message['content']! as List).cast<Block>())
        if (block['type'] == 'tool_use' && block['id'] != null)
          '${block['id']}': '${block['name'] ?? ''}',
};

/// The texts, tool_use blocks and tool_result blocks of a message's content.
({List<String> texts, List<Block> uses, List<Block> results}) splitBlocks(Object? content) {
  if (content is String) return (texts: [content], uses: [], results: []);
  final blocks = (content! as List).cast<Block>();
  List<Block> ofType(String type) => blocks.where((b) => b['type'] == type).toList();
  return (
    texts: [for (final b in ofType('text')) '${b['text'] ?? ''}'],
    uses: ofType('tool_use'),
    results: ofType('tool_result'),
  );
}

/// Tool arguments as a map: JSON text is parsed, a map copied, anything odd kept raw.
Map<String, Object?> parseArguments(Object? raw) {
  if (raw is Map) return Map<String, Object?>.from(raw);
  if (raw == null || raw == '') return {};
  try {
    if (jsonDecode('$raw') case final Map<String, Object?> parsed) return parsed;
  } on FormatException {
    // kept raw below
  }
  return {'__raw': '$raw'};
}

final _random = Random();

/// An id for a tool call the provider returned without one.
String synthesizedToolId() =>
    'toolu_${List.generate(12, (_) => _random.nextInt(16).toRadixString(16)).join()}';

/// The block that tells the user an answer was cut short.
Block stoppedEarly(Object? reason) => {
  'type': 'text',
  'text': '[The model stopped early: $reason.]',
};
