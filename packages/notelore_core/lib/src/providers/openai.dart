/// GPT over the Chat Completions API.
///
/// Translation at the boundary: assistant `tool_use` blocks become `tool_calls`
/// with JSON-string arguments, user `tool_result` blocks become `role: tool`
/// messages, and the completion comes back as Anthropic-style blocks.
library;

import 'dart:convert';

import 'base.dart';
import 'http.dart';

const openAIApi = 'https://api.openai.com/v1/chat/completions';
const openAIModels = 'https://api.openai.com/v1/models';
const _timeout = Duration(seconds: 60);

Map<String, String> openAIHeaders(String apiKey) => {'Authorization': 'Bearer $apiKey'};

/// Tools in the function-calling shape OpenAI and Ollama share.
List<Map<String, Object?>> functionTools(List<Tool> tools) => [
  for (final t in tools)
    {
      'type': 'function',
      'function': {'name': t.name, 'description': t.description, 'parameters': t.inputSchema},
    },
];

class OpenAIProvider implements LlmProvider {
  OpenAIProvider(this._apiKey, this.model, {this.transport = defaultTransport});

  final String _apiKey;
  @override
  final String model;
  final Transport transport;

  @override
  Future<AgentResponse> turn(String system, List<Message> messages, List<Tool> tools) async {
    final answer = await transport(
      'POST',
      openAIApi,
      headers: openAIHeaders(_apiKey),
      body: {
        'model': model,
        'messages': [
          if (system.isNotEmpty) {'role': 'system', 'content': system},
          ...toOpenAI(messages),
        ],
        if (tools.isNotEmpty) 'tools': functionTools(tools),
      },
      timeout: _timeout,
    );
    return fromOpenAI(answer! as Map<String, Object?>);
  }
}

List<Map<String, Object?>> toOpenAI(List<Message> messages) => [
  for (final message in messages) ..._toOpenAI(message),
];

List<Map<String, Object?>> _toOpenAI(Message message) {
  final (:texts, :uses, :results) = splitBlocks(message['content']);
  if (message['role'] == 'assistant') {
    return [
      {
        'role': 'assistant',
        'content': texts.join().isEmpty ? null : texts.join(),
        if (uses.isNotEmpty) 'tool_calls': uses.map(_toolCall).toList(),
      },
    ];
  }
  return [
    for (final r in results)
      {'role': 'tool', 'tool_call_id': r['tool_use_id'] ?? '', 'content': r['content'] ?? ''},
    for (final text in texts) {'role': 'user', 'content': text},
  ];
}

Map<String, Object?> _toolCall(Block use) => {
  'id': use['id'] ?? '',
  'type': 'function',
  'function': {
    'name': use['name'] ?? '',
    'arguments': jsonEncode(use['input'] ?? const <String, Object?>{}),
  },
};

AgentResponse fromOpenAI(Map<String, Object?> completion) {
  final choices = (completion['choices'] as List? ?? const []).cast<Map<String, Object?>>();
  if (choices.isEmpty) return const AgentResponse([], 'end_turn');
  final message = choices.first['message'] as Map<String, Object?>? ?? const {};
  final blocks = <Block>[
    if (message['content'] case final String text when text.isNotEmpty)
      {'type': 'text', 'text': text},
    for (final call in (message['tool_calls'] as List? ?? const []).cast<Map<String, Object?>>())
      {
        'type': 'tool_use',
        'id': call['id'] ?? '',
        'name': (call['function']! as Map)['name'],
        'input': parseArguments((call['function']! as Map)['arguments']),
      },
  ];
  final toolUse = blocks.any((b) => b['type'] == 'tool_use');
  final finish = choices.first['finish_reason'];
  if (!toolUse && finish != null && finish != 'stop') blocks.add(stoppedEarly(finish));
  return AgentResponse(blocks, toolUse ? 'tool_use' : 'end_turn');
}
