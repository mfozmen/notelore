/// Gemini over the Generative Language REST API (v1beta).
///
/// Translation at the boundary: Anthropic-style messages become `contents` with
/// `user` / `model` roles (function responses go under `user`), tools become
/// `functionDeclarations` with a plain JSON Schema, and response parts come back
/// as blocks. Gemini does not always return a call id, so one is synthesized.
library;

import 'base.dart';
import 'http.dart';

const geminiModels = 'https://generativelanguage.googleapis.com/v1beta/models';
const _timeout = Duration(seconds: 60);

String geminiEndpoint(String model) => '$geminiModels/$model:generateContent';

Map<String, String> geminiHeaders(String apiKey) => {'x-goog-api-key': apiKey};

class GeminiProvider implements LlmProvider {
  GeminiProvider(this._apiKey, this.model, {this.transport = defaultTransport});

  final String _apiKey;
  @override
  final String model;
  final Transport transport;

  @override
  Future<AgentResponse> turn(String system, List<Message> messages, List<Tool> tools) async {
    final answer = await transport(
      'POST',
      geminiEndpoint(model),
      headers: geminiHeaders(_apiKey),
      body: {
        'contents': toGemini(messages),
        if (system.isNotEmpty)
          'systemInstruction': {
            'parts': [
              {'text': system},
            ],
          },
        if (tools.isNotEmpty)
          'tools': [
            {
              'functionDeclarations': [
                for (final t in tools)
                  {
                    'name': t.name,
                    'description': t.description,
                    'parametersJsonSchema': t.inputSchema,
                  },
              ],
            },
          ],
      },
      timeout: _timeout,
    );
    return fromGemini(answer! as Map<String, Object?>);
  }
}

List<Map<String, Object?>> toGemini(List<Message> messages) {
  final names = toolUseNames(messages);
  return [
    for (final message in messages)
      if (splitBlocks(message['content']) case (:final texts, :final uses, :final results))
        {
          // Function responses go under role "user", like plain user text.
          'role': message['role'] == 'user' ? 'user' : 'model',
          'parts': [
            for (final t in texts) {'text': t},
            for (final u in uses)
              {
                'functionCall': {
                  'name': u['name'] ?? '',
                  'args': u['input'] ?? const <String, Object?>{},
                },
              },
            for (final r in results)
              {
                'functionResponse': {
                  'name': names['${r['tool_use_id'] ?? ''}'] ?? '',
                  'response': {'result': r['content'] ?? ''},
                },
              },
          ],
        },
  ];
}

AgentResponse fromGemini(Map<String, Object?> answer) {
  final candidates = (answer['candidates'] as List? ?? const []).cast<Map<String, Object?>>();
  if (candidates.isEmpty) return const AgentResponse([], 'end_turn');
  final candidate = candidates.first;
  final content = candidate['content'] as Map<String, Object?>? ?? const {};
  final blocks = <Block>[
    for (final part in (content['parts'] as List? ?? const []).cast<Map<String, Object?>>())
      if (part['text'] case final String text when text.isNotEmpty)
        {'type': 'text', 'text': text}
      else if (part['functionCall'] case final Map<String, Object?> call)
        {
          'type': 'tool_use',
          'id': call['id'] ?? synthesizedToolId(),
          'name': call['name'],
          'input': Map<String, Object?>.from(call['args'] as Map? ?? const {}),
        },
  ];
  final toolUse = blocks.any((b) => b['type'] == 'tool_use');
  final finish = '${candidate['finishReason'] ?? 'STOP'}'.toUpperCase();
  if (!toolUse && finish != 'STOP' && finish != 'FINISH_REASON_UNSPECIFIED') {
    blocks.add(stoppedEarly(finish));
  }
  return AgentResponse(blocks, toolUse ? 'tool_use' : 'end_turn');
}
