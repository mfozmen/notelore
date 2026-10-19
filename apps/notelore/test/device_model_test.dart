import 'package:flutter_test/flutter_test.dart';
import 'package:llamadart/llamadart.dart';
import 'package:notelore/src/device_model.dart';

void main() {
  test('the model is one pinned, checksummed file (#328)', () {
    final file = deviceModelFiles.single;
    expect(file.name, endsWith('.gguf'));
    expect(file.url, contains('/resolve/a06e946bb6b655725eafa393f4a9745d460374c9/'));
    expect(file.sha256, hasLength(64));
    expect(file.size, 2497281120);
  });

  test("Notelore's turn goes to llama.cpp as its own messages", () {
    final messages = toLlama([
      {'role': 'system', 'content': 'You are Notelore.'},
      {'role': 'user', 'content': 'Mopsos: weekly.'},
      {
        'role': 'assistant',
        'content': 'On it.',
        'tool_calls': [
          {
            'function': {
              'name': 'add_note_entry',
              'arguments': {'slug': 'mopsos', 'text': 'Weekly.'},
            },
          },
        ],
      },
      {'role': 'tool', 'content': 'ok', 'tool_name': 'add_note_entry'},
      {'role': 'assistant', 'content': ''},
    ]);
    expect(messages.map((m) => m.role), [
      LlamaChatRole.system,
      LlamaChatRole.user,
      LlamaChatRole.assistant,
      LlamaChatRole.tool,
      LlamaChatRole.assistant,
    ]);
    expect(messages[0].content, 'You are Notelore.');
    expect(messages[1].content, 'Mopsos: weekly.');
    final [said, call] = messages[2].parts;
    expect((said as LlamaTextContent).text, 'On it.');
    call as LlamaToolCallContent;
    expect(call.name, 'add_note_entry');
    expect(call.arguments, {'slug': 'mopsos', 'text': 'Weekly.'});
    expect(call.rawJson, '{"slug":"mopsos","text":"Weekly."}');
    final result = messages[3].parts.single as LlamaToolResultContent;
    expect((result.name, result.result), ('add_note_entry', 'ok'));
    expect(messages[4].parts, isEmpty); // an empty answer, no empty text part
  });

  test('the tools go as their JSON schemas, for the tool-call grammar', () {
    final tools = toolsFor([
      {
        'type': 'function',
        'function': {
          'name': 'add_note_entry',
          'description': 'Append a dated note.',
          'parameters': {
            'type': 'object',
            'properties': {
              'slug': {'type': 'string'},
            },
            'required': ['slug'],
          },
        },
      },
    ]);
    expect(tools.single.name, 'add_note_entry');
    expect(tools.single.description, 'Append a dated note.');
    expect(tools.single.toJsonSchema()['required'], ['slug']);
  });

  test("llama.cpp's answer comes back in the shape the provider reads", () {
    final reply = fromLlama(
      const LlamaCompletion(
        text: 'Saved.',
        toolCalls: [
          LlamaToolCallContent(
            name: 'add_note_entry',
            arguments: {'slug': 'mopsos'},
            rawJson: '{"slug":"mopsos"}',
          ),
        ],
        usage: LlamaGenerationUsage(promptTokens: 2707, completionTokens: 31),
      ),
    );
    expect(reply, {
      'message': {
        'content': 'Saved.',
        'tool_calls': [
          {
            'function': {
              'name': 'add_note_entry',
              'arguments': {'slug': 'mopsos'},
            },
          },
        ],
      },
      'prompt_eval_count': 2707,
      'eval_count': 31,
    });
    expect(fromLlama(const LlamaCompletion(text: 'Hi.')), {
      'message': {'content': 'Hi.', 'tool_calls': <Object?>[]},
    });
  });
}
