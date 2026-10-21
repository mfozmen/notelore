/// DeepSeek over its OpenAI-compatible Chat Completions API.
library;

import 'dart:convert';

import 'base.dart';
import 'http.dart';
import 'openai.dart' show functionTools;

const deepSeekChat = 'https://api.deepseek.com/chat/completions';
const deepSeekModels = 'https://api.deepseek.com/models';

Map<String, String> deepSeekHeaders(String apiKey) => {'Authorization': 'Bearer $apiKey'};

const _timeout = Duration(seconds: 120);

class DeepSeekProvider implements LlmProvider {
  DeepSeekProvider(this._apiKey, this.model, {this.transport = defaultTransport});

  final String _apiKey;

  @override
  final String model;
  final Transport transport;

  @override
  Future<AgentResponse> turn(String system, List<Message> messages, List<Tool> tools) async {
    final answer = await transport(
      'POST',
      deepSeekChat,
      headers: deepSeekHeaders(_apiKey),
      body: {
        'model': model,
        'messages': [
          if (system.isNotEmpty) {'role': 'system', 'content': system},
          ...toDeepSeek(messages),
        ],
        'stream': false,
        // Thinking is on by default and billed as output; note turns do not need it.
        'thinking': {'type': 'disabled'},
        if (tools.isNotEmpty) 'tools': functionTools(tools),
      },
      timeout: _timeout,
    );
    return fromDeepSeek(answer);
  }
}

List<Map<String, Object?>> toDeepSeek(List<Message> messages) => [
  for (final message in messages) ..._toDeepSeek(message),
];

List<Map<String, Object?>> _toDeepSeek(Message message) {
  final (:texts, :uses, :results, :images) = splitBlocks(message['content']);
  if (message['role'] == 'assistant') return [_assistantMessage(texts, uses)];
  return [
    for (final result in results)
      {
        'role': 'tool',
        'tool_call_id': result['tool_use_id'] ?? '',
        'content': result['content'] ?? '',
      },
    ..._userMessages(texts, images),
  ];
}

Map<String, Object?> _assistantMessage(List<String> texts, List<Block> uses) => {
  'role': 'assistant',
  'content': texts.join(),
  if (uses.any((use) => use['id'] != null))
    'tool_calls': [
      for (final use in uses)
        if (use['id'] != null)
          {
            'id': '${use['id']}',
            'type': 'function',
            'function': {
              'name': use['name'] ?? '',
              'arguments': jsonEncode(use['input'] ?? const <String, Object?>{}),
            },
          },
    ],
};

List<Map<String, Object?>> _userMessages(List<String> texts, List<Block> images) {
  if (images.isEmpty) {
    return [
      for (final text in texts) {'role': 'user', 'content': text},
    ];
  }
  return [
    {
      'role': 'user',
      'content': [
        for (final text in texts) {'type': 'text', 'text': text},
        for (final image in images)
          {
            'type': 'image_url',
            'image_url': {'url': _imageUrl(image)},
          },
      ],
    },
  ];
}

String _imageUrl(Block image) {
  final (mediaType, data) = imageData(image);
  return 'data:$mediaType;base64,$data';
}

AgentResponse fromDeepSeek(Object? answer) {
  if (answer is! Map) return const AgentResponse([], 'end_turn');
  final choices = answer['choices'];
  if (choices is! List || choices.isEmpty) return const AgentResponse([], 'end_turn');
  final choice = choices.first;
  if (choice is! Map) return const AgentResponse([], 'end_turn');
  final message = choice['message'];
  if (message is! Map) return const AgentResponse([], 'end_turn');
  final blocks = _deepSeekBlocks(message);
  final finish = choice['finish_reason'];
  final toolUse = finish == 'tool_calls' && blocks.any((block) => block['type'] == 'tool_use');
  if (!toolUse && finish is String && finish != 'stop') blocks.add(stoppedEarly(finish));
  return AgentResponse(blocks, toolUse ? 'tool_use' : 'end_turn', usage: _deepSeekUsage(answer));
}

List<Block> _deepSeekBlocks(Map<Object?, Object?> message) => [
  if (message['content'] case final String text when text.isNotEmpty)
    {'type': 'text', 'text': text},
  for (final call
      in (message['tool_calls'] as List? ?? const []).whereType<Map<Object?, Object?>>())
    if (call['function'] case final Map<Object?, Object?> function)
      {
        'type': 'tool_use',
        'id': call['id'] == null ? synthesizedToolId() : '${call['id']}',
        'name': function['name'] ?? '',
        'input': parseArguments(function['arguments']),
      },
];

TokenUsage? _deepSeekUsage(Object? answer) => switch (answer) {
  {'usage': {'prompt_tokens': final int input, 'completion_tokens': final int output}} =>
    TokenUsage(input, output),
  _ => null,
};
