import 'package:notelore_core/src/providers/gemini.dart';
import 'package:test/test.dart';

import 'base_test.dart' show conversation, tool;
import 'fake_api.dart';

Map<String, Object?> candidate(List<Object?> parts, [String finish = 'STOP']) => {
  'candidates': [
    {
      'content': {'role': 'model', 'parts': parts},
      'finishReason': finish,
    },
  ],
};

void main() {
  test('toGemini roles and function parts', () {
    expect(toGemini(conversation), [
      {
        'role': 'user',
        'parts': [
          {'text': 'hi'},
        ],
      },
      {
        'role': 'model',
        'parts': [
          {'text': 'checking'},
          {
            'functionCall': {
              'name': 'read_note',
              'args': {'slug': 'x'},
            },
          },
          {
            'functionCall': {'name': 'no-id-is-skipped', 'args': <String, Object?>{}},
          },
        ],
      },
      // Gemini expects function responses under role "user"
      {
        'role': 'user',
        'parts': [
          {
            'functionResponse': {
              'name': 'read_note',
              'response': {'result': 'ok'},
            },
          },
        ],
      },
    ]);
  });

  test('fromGemini variants', () {
    expect(fromGemini({}).content, isEmpty);
    expect(
      fromGemini({
        'candidates': [
          {'finishReason': 'SAFETY'},
        ],
      }).content,
      [
        {'type': 'text', 'text': '[The model stopped early: SAFETY.]'},
      ],
    );
    final text = fromGemini(
      candidate([
        {'text': 'hello'},
      ]),
    );
    expect(text.content, [
      {'type': 'text', 'text': 'hello'},
    ]);
    expect(text.stopReason, 'end_turn');
    final tool = fromGemini(
      candidate([
        {
          'functionCall': {
            'id': 'g1',
            'name': 'read_note',
            'args': {'slug': 'x'},
          },
        },
        {
          'functionCall': {'name': 'search_notes'},
        },
      ]),
    );
    expect(tool.stopReason, 'tool_use');
    expect(tool.content[0], {
      'type': 'tool_use',
      'id': 'g1',
      'name': 'read_note',
      'input': {'slug': 'x'},
    });
    expect(tool.content[1]['id'], startsWith('toolu_'));
    expect(tool.content[1]['input'], <String, Object?>{});
    expect(
      fromGemini(
        candidate([
          {'thought': true},
        ]),
      ).content,
      isEmpty,
    );
    final unspecified = fromGemini({
      'candidates': [
        {'finishReason': 'FINISH_REASON_UNSPECIFIED'},
      ],
    });
    expect(unspecified.content, isEmpty);
  });

  test('turn posts generateContent', () async {
    final api = Api()
      ..answers.addAll([
        candidate([
          {'text': 'ok'},
        ]),
        candidate([
          {'text': 'ok'},
        ]),
      ]);
    final provider = GeminiProvider('gk', 'gemini-x', transport: api.call);
    final hi = [
      {'role': 'user', 'content': 'hi'},
    ];
    expect((await provider.turn('be brief', hi, [tool])).content, [
      {'type': 'text', 'text': 'ok'},
    ]);
    final call = api.last;
    expect((call['method'], call['url']), ('POST', geminiEndpoint('gemini-x')));
    expect(call['url'], endsWith('/v1beta/models/gemini-x:generateContent'));
    expect(call['headers'], {'x-goog-api-key': 'gk'});
    expect(call['body'], {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': 'hi'},
          ],
        },
      ],
      'systemInstruction': {
        'parts': [
          {'text': 'be brief'},
        ],
      },
      'tools': [
        {
          'functionDeclarations': [
            {
              'name': 'read_note',
              'description': 'Read a note',
              'parametersJsonSchema': tool.inputSchema,
            },
          ],
        },
      ],
    });
    await provider.turn('', hi, []);
    expect((api.last['body']! as Map).keys, ['contents']);
  });
}
