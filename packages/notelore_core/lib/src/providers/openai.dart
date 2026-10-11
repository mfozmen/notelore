/// OpenAI's model listing (key check) and the function-tool shape Ollama shares.
/// Turns with an API key go over the Responses API (`chatgpt.dart`): newer
/// models take function tools only there.
library;

import 'base.dart';

const openAIModels = 'https://api.openai.com/v1/models';

Map<String, String> openAIHeaders(String apiKey) => {'Authorization': 'Bearer $apiKey'};

/// Tools in the function-calling shape OpenAI and Ollama share.
List<Map<String, Object?>> functionTools(List<Tool> tools) => [
  for (final t in tools)
    {
      'type': 'function',
      'function': {'name': t.name, 'description': t.description, 'parameters': t.inputSchema},
    },
];
