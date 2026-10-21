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
  DeepSeekProvider(this.apiKey, this.model, {this.transport = defaultTransport});

  final String apiKey;

  @override
  final String model;
  final Transport transport;

  @override
  Future<AgentResponse> turn(String system, List<Message> messages, List<Tool> tools) async {
    final answer = await transport(
      'POST',
      deepSeekChat,
      headers: deepSeekHeaders(apiKey),
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
  if (message['role'] == 'assistant') {
    return [
      {
        'role': 'assistant',
        'content': texts.join(),
        if (uses.any((u) => u['id'] != null))
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
      },
    ];
  }
  return [
    for (final result in results)
      {
        'role': 'tool',
        'tool_call_id': result['tool_use_id'] ?? '',
        'content': result['content'] ?? '',
      },
    if (images.isEmpty)
      for (final text in texts) {'role': 'user', 'content': text}
    else
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
  final message = (choices.first as Map<Object?, Object?>)['message'];
  if (message is! Map) return const AgentResponse([], 'end_turn');
  final blocks = <Block>[
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
  final usage = switch (answer['usage']) {
    {'prompt_tokens': final int input, 'completion_tokens': final int output} => TokenUsage(
      input,
      output,
    ),
    _ => null,
  };
  final toolUse = blocks.any((block) => block['type'] == 'tool_use');
  return AgentResponse(blocks, toolUse ? 'tool_use' : 'end_turn', usage: usage);
}
