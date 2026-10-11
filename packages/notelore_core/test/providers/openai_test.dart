import 'package:notelore_core/src/providers/openai.dart';
import 'package:test/test.dart';

import 'base_test.dart' show tool;

void main() {
  test('the key header and the function-tool shape Ollama shares', () {
    expect(openAIHeaders('sk-1'), {'Authorization': 'Bearer sk-1'});
    expect(functionTools([tool]), [
      {
        'type': 'function',
        'function': {
          'name': 'read_note',
          'description': 'Read a note',
          'parameters': tool.inputSchema,
        },
      },
    ]);
  });
}
