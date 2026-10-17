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

/// How a provider is paid for; the setup screen groups providers by it.
enum ProviderGroup {
  plan('Use your plan', "No extra charges, within your plan's limits."),
  apiKey('API key', 'Billed per use by the provider; Gemini has a free tier.'),
  local('On this computer', 'Free: the model runs here.');

  const ProviderGroup(this.heading, this.explanation);

  final String heading;
  final String explanation;
}

final class ProviderSpec {
  const ProviderSpec(
    this.name,
    this.displayName, {
    required this.group,
    required this.requiresApiKey,
    required this.defaultModel,
    this.keyUrl,
    this.keySteps = const [],
    required this.cost,
    this.webSearch = false,
    this.images = false,
  });

  final String name;
  final String displayName;
  final ProviderGroup group;
  final bool requiresApiKey;
  final String defaultModel;
  final String? keyUrl;
  final List<String> keySteps;

  /// What using it costs, shown before a key is asked for.
  final String cost;

  /// The model can look things up on the web through the provider's own tool.
  final bool webSearch;

  /// The models take images with a message (#278). Ollama's may or may not,
  /// depending on the local model, so it is not offered there.
  final bool images;
}

const providerSpecs = [
  ProviderSpec(
    'chatgpt',
    'ChatGPT plan (OpenAI)',
    group: ProviderGroup.plan,
    webSearch: true,
    images: true,
    requiresApiKey: false,
    defaultModel: '', // the first model the plan lists
    cost: "Uses your ChatGPT Plus or Pro plan: no separate charges, within your plan's limits.",
  ),
  ProviderSpec(
    'anthropic',
    'Claude (Anthropic)',
    group: ProviderGroup.apiKey,
    webSearch: true,
    images: true,
    requiresApiKey: true,
    defaultModel: 'claude-sonnet-5-5',
    cost:
        'Billed per use through the Anthropic API. A Claude Pro or Max subscription cannot '
        'be used in other apps.',
    keyUrl: 'https://console.anthropic.com/settings/keys',
    keySteps: [
      'Sign in to the Anthropic Console (a free account is enough).',
      'Choose Create Key, give it a name such as notelore, and copy it.',
      'Paste the key below (it starts with sk-ant-).',
    ],
  ),
  ProviderSpec(
    'openai',
    'GPT (OpenAI)',
    group: ProviderGroup.apiKey,
    webSearch: true,
    images: true,
    requiresApiKey: true,
    defaultModel: 'gpt-4o-mini',
    cost:
        'Billed per use through the OpenAI API. To use a ChatGPT Plus or Pro plan instead, '
        'pick "ChatGPT plan".',
    keyUrl: 'https://platform.openai.com/api-keys',
    keySteps: [
      'Sign in to the OpenAI Platform.',
      'Choose Create new secret key, give it a name, and copy it.',
      'Paste the key below (it starts with sk-).',
    ],
  ),
  ProviderSpec(
    'gemini',
    'Gemini (Google)',
    group: ProviderGroup.apiKey,
    images: true,
    requiresApiKey: true,
    defaultModel: 'gemini-2.5-flash',
    cost:
        'Free with a key from a Google AI Studio project without billing: rate limited, and '
        'Google may use free-tier requests to improve its products. Billed per use otherwise.',
    keyUrl: 'https://aistudio.google.com/apikey',
    keySteps: [
      'Sign in to Google AI Studio.',
      'Choose Create API key and copy it.',
      'Paste the key below.',
    ],
  ),
  ProviderSpec(
    'ollama',
    'Ollama (local)',
    group: ProviderGroup.local,
    requiresApiKey: false,
    defaultModel: 'llama3.2',
    cost: 'Free: the model runs on this computer.',
  ),
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

/// The tokens one model call used, as the provider reported them.
final class TokenUsage {
  const TokenUsage(this.input, this.output);

  final int input;
  final int output;
}

final class AgentResponse {
  const AgentResponse(this.content, this.stopReason, {this.usage});

  final List<Block> content;

  /// "end_turn" | "tool_use"
  final String stopReason;

  /// Null when the provider did not say: never estimated.
  final TokenUsage? usage;
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

/// The texts, tool_use, tool_result and image blocks of a message's content.
({List<String> texts, List<Block> uses, List<Block> results, List<Block> images}) splitBlocks(
  Object? content,
) {
  if (content is String) return (texts: [content], uses: [], results: [], images: []);
  final blocks = (content! as List).cast<Block>();
  List<Block> ofType(String type) => blocks.where((b) => b['type'] == type).toList();
  return (
    texts: [for (final b in ofType('text')) '${b['text'] ?? ''}'],
    uses: ofType('tool_use'),
    results: ofType('tool_result'),
    images: ofType('image'),
  );
}

/// The image type [bytes] start with (PNG, JPEG, GIF, WebP: what every
/// provider here takes), or null for anything else.
String? imageType(List<int> bytes) {
  bool starts(List<int> magic, [int at = 0]) =>
      bytes.length >= at + magic.length &&
      [for (var i = 0; i < magic.length; i++) bytes[at + i] == magic[i]].every((same) => same);
  if (starts(const [0x89, 0x50, 0x4e, 0x47])) return 'image/png';
  if (starts(const [0xff, 0xd8, 0xff])) return 'image/jpeg';
  if (starts('GIF8'.codeUnits)) return 'image/gif';
  if (starts('RIFF'.codeUnits) && starts('WEBP'.codeUnits, 8)) return 'image/webp';
  return null;
}

/// An image as a content block, in Anthropic's shape like every block here.
Block imageBlock(String mediaType, List<int> bytes) => {
  'type': 'image',
  'source': {'type': 'base64', 'media_type': mediaType, 'data': base64Encode(bytes)},
};

/// [image]'s type and its bytes as base64, for the providers' own shapes.
(String mediaType, String data) imageData(Block image) {
  final source = image['source']! as Map<String, Object?>;
  return ('${source['media_type']}', '${source['data']}');
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
