/// A model on this device (#328): no server, no key, nothing leaves the device.
///
/// The model runs through llama.cpp in the app ([LocalEngine]); this side only
/// speaks to it in the OpenAI-like shape Ollama uses too, so tool calls, tool
/// results and a thinking model's leaked reasoning are handled the same way.
library;

import 'base.dart';
import 'ollama.dart' show fromOllama, toOllama;
import 'openai.dart' show functionTools;

/// One chat completion on the device. [messages] and [tools] come in the
/// OpenAI-like shape; the reply is Ollama's: `{message: {content, tool_calls}}`
/// and, when the runtime counts them, `prompt_eval_count` and `eval_count`.
abstract interface class LocalEngine {
  Future<Map<String, Object?>> chat(
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools,
  );
}

/// The device could not load or run the model: too little memory, or a file
/// the runtime refuses. The chat says so; another model can be chosen.
class LocalModelFailed implements Exception {
  const LocalModelFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The model on the device, whose [engine] the app supplies. Like Ollama, the
/// runtime gives tool calls no ids (fromOllama makes them) and its tool
/// results are matched to their call by the tool's name.
class LocalProvider implements LlmProvider {
  LocalProvider(this.model, this.engine);

  @override
  final String model;
  final LocalEngine engine;

  @override
  Future<AgentResponse> turn(String system, List<Message> messages, List<Tool> tools) async =>
      fromOllama(
        await engine.chat([
          if (system.isNotEmpty) {'role': 'system', 'content': system},
          ...toOllama(messages),
        ], functionTools(tools)),
      );
}
