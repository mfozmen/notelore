/// Claude over the Messages API. Native content-block format: no translation.
library;

import 'base.dart';
import 'http.dart';

const anthropicApi = 'https://api.anthropic.com/v1/messages';
const anthropicModels = 'https://api.anthropic.com/v1/models';
const _version = '2023-06-01';
const _maxTokens = 4096;
const _timeout = Duration(seconds: 60); // long enough for a reply, short enough not to freeze

Map<String, String> anthropicHeaders(String apiKey) => {
  'x-api-key': apiKey,
  'anthropic-version': _version,
};

class AnthropicProvider implements LlmProvider {
  AnthropicProvider(this._apiKey, this.model, {this.transport = defaultTransport});

  final String _apiKey;
  @override
  final String model;
  final Transport transport;

  @override
  Future<AgentResponse> turn(String system, List<Message> messages, List<Tool> tools) async {
    final answer = await transport(
      'POST',
      anthropicApi,
      headers: anthropicHeaders(_apiKey),
      body: {
        'model': model,
        'max_tokens': _maxTokens,
        if (system.isNotEmpty) 'system': system,
        'messages': messages,
        if (tools.isNotEmpty)
          'tools': [
            for (final t in tools)
              {'name': t.name, 'description': t.description, 'input_schema': t.inputSchema},
          ],
      },
      timeout: _timeout,
    ) as Map<String, Object?>;
    final blocks = [
      for (final block in (answer['content'] as List? ?? const []).cast<Block>()) blockToMap(block),
    ];
    final stop = answer['stop_reason'];
    if (!const ['end_turn', 'tool_use', 'stop_sequence'].contains(stop)) {
      blocks.add(stoppedEarly(stop));
    }
    return AgentResponse(blocks, stop == 'tool_use' ? 'tool_use' : 'end_turn');
  }
}

/// Only the fields the API accepts back in history (it rejects response-only ones).
Block blockToMap(Block block) => switch (block['type']) {
  'text' => {'type': 'text', 'text': block['text']},
  'tool_use' => {
    'type': 'tool_use',
    'id': block['id'],
    'name': block['name'],
    'input': block['input'],
  },
  final kind => {'type': kind},
};
