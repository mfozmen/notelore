import 'package:notelore_core/src/providers/anthropic.dart';
import 'package:test/test.dart';

import 'base_test.dart' show tool;
import 'fake_api.dart';

void main() {
  late Api api;
  setUp(() => api = Api());

  test('turn posts the Messages API', () async {
    api.answers.add({
      'content': [
        {'type': 'text', 'text': 'hi', 'citations': null},
      ],
      'stop_reason': 'end_turn',
    });
    final response = await AnthropicProvider('sk-ant', 'claude-x', transport: api.call).turn(
      'be brief',
      [
        {'role': 'user', 'content': 'hello'},
      ],
      [tool],
    );
    expect(response.stopReason, 'end_turn');
    expect(response.content, [
      {'type': 'text', 'text': 'hi'}, // response-only fields dropped
    ]);
    final call = api.last;
    expect((call['method'], call['url']), ('POST', anthropicApi));
    expect(call['headers'], {'x-api-key': 'sk-ant', 'anthropic-version': '2023-06-01'});
    expect(call['body'], {
      'model': 'claude-x',
      'max_tokens': 4096,
      'system': 'be brief',
      'messages': [
        {'role': 'user', 'content': 'hello'},
      ],
      'tools': [
        {'name': 'read_note', 'description': 'Read a note', 'input_schema': tool.inputSchema},
      ],
    });
    expect(call['timeout'], const Duration(seconds: 60));
  });

  test('tool use, and no tools or system', () async {
    api.answers.add({
      'content': [
        {
          'type': 'tool_use',
          'id': 't1',
          'name': 'read_note',
          'input': {'slug': 'x'},
        },
      ],
      'stop_reason': 'tool_use',
    });
    final response = await AnthropicProvider('sk', 'm', transport: api.call).turn('', [], []);
    final body = api.last['body']! as Map<String, Object?>;
    expect(body.containsKey('tools'), isFalse);
    expect(body.containsKey('system'), isFalse);
    expect(response.stopReason, 'tool_use');
    expect(response.content, [
      {
        'type': 'tool_use',
        'id': 't1',
        'name': 'read_note',
        'input': {'slug': 'x'},
      },
    ]);
  });

  test('a max_tokens cutoff is reported', () async {
    api.answers.add({
      'content': [
        {'type': 'text', 'text': 'partial'},
      ],
      'stop_reason': 'max_tokens',
    });
    final response = await AnthropicProvider('sk', 'm', transport: api.call).turn('', [], []);
    expect(response.stopReason, 'end_turn');
    expect(response.content[1], {'type': 'text', 'text': '[The model stopped early: max_tokens.]'});
  });

  test('an answer without content is empty', () async {
    api.answers.add({'stop_reason': 'end_turn'});
    final response = await AnthropicProvider('sk', 'm', transport: api.call).turn('', [], []);
    expect(response.content, isEmpty);
  });

  test('blockToMap whitelists fields', () {
    expect(blockToMap({'type': 'text', 'text': 'hi', 'extra': 1}), {'type': 'text', 'text': 'hi'});
    expect(blockToMap({'type': 'thinking', 'thinking': '...'}), {'type': 'thinking'});
  });
}
