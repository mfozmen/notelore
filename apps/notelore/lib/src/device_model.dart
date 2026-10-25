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
/// Another model family has other control tokens: [_inert] must follow.
const deviceModelFiles = [
  ModelFile(
    'Qwen3-4B-Instruct-2507-Q4_K_M.gguf',
    '$_qwen/Qwen3-4B-Instruct-2507-Q4_K_M.gguf',
    '3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597',
    2497281120,
  ),
];

/// Where the model on the device is offered (#328): the desktops llama.cpp
/// runs on, and an Android phone with a 64-bit runtime and at least 6 GB of
/// memory ([meminfo] is `/proc/meminfo`); a smaller one is killed loading it.
bool deviceModelRuns({required String os, required String dartVersion, String? meminfo}) {
  if (os == 'windows' || os == 'macos') return true;
  if (os != 'android') return false;
  if (!RegExp('android_(arm64|x64)').hasMatch(dartVersion)) return false;
  final kb = RegExp(r'MemTotal:\s*(\d+) kB').firstMatch(meminfo ?? '')?[1];
  return kb != null && int.parse(kb) >= _enoughKb;
}

/// 6 GB as the kernel counts it; a "6 GB" phone reports a little less.
const _enoughKb = 5500000;

/// The phone's fast (performance) cores, not every core (#594): llama.cpp runs
/// about twice as fast on the S23's four performance cores as on all eight,
/// where the efficiency cores hold the decode back. Every core above the
/// slowest cluster counts, less a lone prime core, whose single thread adds
/// little and can slow the rest. [fallback] when none is readable (0 keeps
/// llama.cpp's own choice).
int fastCores(Iterable<int> maxFrequencies, {required int fallback}) {
  final counts = <int, int>{};
  for (final hz in maxFrequencies) {
    if (hz > 0) counts[hz] = (counts[hz] ?? 0) + 1;
  }
  if (counts.isEmpty) return fallback;
  final total = counts.values.fold(0, (sum, count) => sum + count);
  if (counts.length == 1) return total;
  final slowest = counts.keys.reduce((a, b) => a < b ? a : b);
  var fast = total - counts[slowest]!;
  final fastest = counts.keys.reduce((a, b) => a > b ? a : b);
  if (counts.length >= 3 && counts[fastest] == 1) fast--;
  return fast;
}

/// Text a model would read as its own markers (a turn's end, a tool call, its
/// thinking), written so it stays text: llama.cpp parses those tokens even in
/// a message, so a shared note or a web page could otherwise forge a turn.
String _inert(String text) => text.replaceAllMapped(
  RegExp(r'<(\||/?tool_call>|/?tool_response>|/?think>)'),
  (m) => '<\u200B${m[1]}',
);

/// The OpenAI-like messages [LocalProvider] sends, as llama.cpp's. Everything
/// but the app's own system prompt is made [_inert].
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
            LlamaTextContent(_inert(text)),
          for (final call
              in (message['tool_calls'] as List? ?? const []).cast<Map<Object?, Object?>>())
            _call(call['function']! as Map),
        ],
      ),
      'tool' => LlamaChatMessage.withContent(
        role: LlamaChatRole.tool,
        content: [
          LlamaToolResultContent(
            name: '${message['tool_name']}',
            result: _inert('${message['content']}'),
          ),
        ],
      ),
      _ => LlamaChatMessage.fromText(
        role: LlamaChatRole.user,
        text: _inert('${message['content']}'),
      ),
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
