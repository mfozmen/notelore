/// The model that runs on the device (#328): which file it is, and how a
/// turn travels between Notelore and llama.cpp (llamadart). The native calls
/// are in device_native.dart; everything here is plain data and tested.
library;

import 'dart:convert';

import 'package:llamadart/llamadart.dart';

import 'whisper_model.dart' show ModelFile;

const _qwen =
    'https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/a06e946bb6b655725eafa393f4a9745d460374c9';

/// Qwen3 4B Instruct 2507, Q4_K_M (Apache-2.0): the stock model until the
/// fine-tune is published (#445). Pinned to one revision, checked by its hash.
const deviceModelFiles = [
  ModelFile(
    'Qwen3-4B-Instruct-2507-Q4_K_M.gguf',
    '$_qwen/Qwen3-4B-Instruct-2507-Q4_K_M.gguf',
    '3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597',
    2497281120,
  ),
];

/// The OpenAI-like messages [LocalProvider] sends, as llama.cpp's.
List<LlamaChatMessage> toLlama(List<Map<String, Object?>> messages) => [
  for (final message in messages)
    switch (message['role']) {
      'system' => LlamaChatMessage.fromText(
        role: LlamaChatRole.system,
        text: '${message['content']}',
      ),
      'assistant' => LlamaChatMessage.withContent(
        role: LlamaChatRole.assistant,
        content: [
          if (message['content'] case final String text when text.isNotEmpty)
            LlamaTextContent(text),
          for (final call
              in (message['tool_calls'] as List? ?? const []).cast<Map<Object?, Object?>>())
            _call(call['function']! as Map),
        ],
      ),
      'tool' => LlamaChatMessage.withContent(
        role: LlamaChatRole.tool,
        content: [
          LlamaToolResultContent(name: '${message['tool_name']}', result: message['content']),
        ],
      ),
      _ => LlamaChatMessage.fromText(role: LlamaChatRole.user, text: '${message['content']}'),
    },
];

LlamaToolCallContent _call(Map<Object?, Object?> function) {
  final arguments = (function['arguments']! as Map).cast<String, dynamic>();
  return LlamaToolCallContent(
    name: '${function['name']}',
    arguments: arguments,
    rawJson: jsonEncode(arguments),
  );
}

/// The tools as JSON schemas: llama.cpp turns them into the grammar a tool
/// call is generated under, so its arguments are always valid JSON.
List<ToolDefinition> toolsFor(List<Map<String, Object?>> tools) => [
  for (final tool in tools)
    if (tool['function'] case final Map<Object?, Object?> function)
      ToolDefinition.fromJsonSchema(
        name: '${function['name']}',
        description: '${function['description']}',
        schema: (function['parameters']! as Map).cast<String, dynamic>(),
      ),
];

/// llama.cpp's answer in Ollama's shape, which [LocalProvider] reads.
Map<String, Object?> fromLlama(LlamaCompletion completion) => {
  'message': {
    'content': completion.text,
    'tool_calls': [
      for (final call in completion.toolCalls)
        {
          'function': {'name': call.name, 'arguments': call.arguments},
        },
    ],
  },
  if (completion.usage case final usage?) ...{
    'prompt_eval_count': usage.promptTokens,
    'eval_count': usage.completionTokens,
  },
};
