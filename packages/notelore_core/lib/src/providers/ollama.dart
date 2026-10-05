/// Local models over Ollama's REST API (`/api/chat`). Key-less.
///
/// OpenAI-like wire shape with two twists: tool calls carry no id (one is
/// synthesized here) and tool results are correlated by `tool_name`.
library;

import 'dart:io';

import 'base.dart';
import 'http.dart';
import 'openai.dart' show functionTools;

const _defaultHost = 'http://localhost:11434';
const _timeout = Duration(seconds: 180); // a cold local model takes a while for its first token

/// `OLLAMA_HOST` from [environment] (the process environment by default).
String ollamaHost([Map<String, String>? environment]) =>
    ((environment ?? Platform.environment)['OLLAMA_HOST'] ?? _defaultHost).replaceFirst(
      RegExp(r'/+$'),
      '',
    );

class OllamaProvider implements LlmProvider {
  OllamaProvider(this.model, {String? host, this.transport = defaultTransport})
    : _host = host ?? ollamaHost();

  @override
  final String model;
  final String _host;
  final Transport transport;

  @override
  Future<AgentResponse> turn(String system, List<Message> messages, List<Tool> tools) async {
    final answer = await transport(
      'POST',
      '$_host/api/chat',
      body: {
        'model': model,
        'messages': [
          if (system.isNotEmpty) {'role': 'system', 'content': system},
          ...toOllama(messages),
        ],
        'stream': false,
        if (tools.isNotEmpty) 'tools': functionTools(tools),
      },
      timeout: _timeout,
    );
    return fromOllama(answer! as Map<String, Object?>);
  }
}

List<Map<String, Object?>> toOllama(List<Message> messages) {
  final names = toolUseNames(messages);
  return [for (final message in messages) ..._toOllama(message, names)];
}

List<Map<String, Object?>> _toOllama(Message message, Map<String, String> names) {
  final (:texts, :uses, :results) = splitBlocks(message['content']);
  if (message['role'] == 'assistant') {
    return [
      {
        'role': 'assistant',
        'content': texts.join(),
        if (uses.isNotEmpty)
          'tool_calls': [
            for (final u in uses)
              {
                'function': {
                  'name': u['name'] ?? '',
                  'arguments': u['input'] ?? const <String, Object?>{},
                },
              },
          ],
      },
    ];
  }
  return [
    for (final r in results)
      {
        'role': 'tool',
        'content': r['content'] ?? '',
        'tool_name': names['${r['tool_use_id'] ?? ''}'] ?? '',
      },
    for (final text in texts) {'role': 'user', 'content': text},
  ];
}

AgentResponse fromOllama(Map<String, Object?> answer) {
  final message = answer['message'] as Map<String, Object?>?;
  if (message == null) return const AgentResponse([], 'end_turn');
  final blocks = <Block>[
    if (message['content'] case final String text when text.isNotEmpty)
      {'type': 'text', 'text': text},
    for (final call in (message['tool_calls'] as List? ?? const []).cast<Map<String, Object?>>())
      {
        'type': 'tool_use',
        'id': synthesizedToolId(),
        'name': (call['function']! as Map)['name'],
        'input': parseArguments((call['function']! as Map)['arguments']),
      },
  ];
  final toolUse = blocks.any((b) => b['type'] == 'tool_use');
  return AgentResponse(blocks, toolUse ? 'tool_use' : 'end_turn');
}
