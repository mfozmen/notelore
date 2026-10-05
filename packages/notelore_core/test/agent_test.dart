import 'dart:convert';
import 'dart:io';

import 'package:notelore_core/src/agent.dart';
import 'package:notelore_core/src/providers/base.dart';
import 'package:notelore_core/src/providers/http.dart';
import 'package:notelore_core/src/tools.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'tools_test.dart' show newBox, today;

/// Returns the scripted responses in order and records every turn.
class ScriptedProvider implements LlmProvider {
  ScriptedProvider(this.responses);

  final List<AgentResponse> responses;
  final turns = <(String, List<Message>, List<Tool>)>[];

  @override
  String get model => 'scripted';

  @override
  Future<AgentResponse> turn(String system, List<Message> messages, List<Tool> tools) async {
    // A deep copy: the agent keeps appending to its history after the turn.
    turns.add((system, (jsonDecode(jsonEncode(messages)) as List).cast<Message>(), tools));
    return responses.removeAt(0);
  }
}

AgentResponse text(String content) => AgentResponse([
  {'type': 'text', 'text': content},
], 'end_turn');

AgentResponse toolUse(String name, [String id = 't1', Map<String, Object?> args = const {}]) =>
    AgentResponse([
      {'type': 'text', 'text': 'checking'},
      {'type': 'tool_use', 'id': id, 'name': name, 'input': args},
    ], 'tool_use');

/// The content of the last tool result the provider saw on [turn].
Object? lastResult(ScriptedProvider provider, int turn) =>
    ((provider.turns[turn].$2.last['content']! as List).first as Map)['content'];

void main() {
  failureTests();
  late Toolbox box;
  setUp(() => box = newBox());

  test('a plain answer keeps the history', () async {
    final provider = ScriptedProvider([text('Merhaba!')]);
    final agent = Agent(provider, box, today: today);
    expect(await agent.ask('selam'), 'Merhaba!');
    final (system, messages, tools) = provider.turns.single;
    expect(system, contains('2026-09-30'));
    expect(messages, [
      {'role': 'user', 'content': 'selam'},
    ]);
    expect(tools, box.tools);
    expect(agent.messages.last, {
      'role': 'assistant',
      'content': [
        {'type': 'text', 'text': 'Merhaba!'},
      ],
    });
  });

  test('tool calls run and their results go back', () async {
    final provider = ScriptedProvider([
      toolUse('create_note', 't1', {'kind': 'project', 'title': 'Mopsos'}),
      toolUse('add_note_entry', 't2', {'slug': 'mopsos', 'text': 'Weekly hit rate.'}),
      text('Noted.'),
    ]);
    final agent = Agent(provider, box, today: today);
    expect(await agent.ask('Mopsos için not al: haftalık isabet oranı'), 'Noted.');
    expect(provider.turns, hasLength(3));
    expect(provider.turns[1].$2.last, {
      'role': 'user',
      'content': [
        {
          'type': 'tool_result',
          'tool_use_id': 't1',
          'content': '{"slug":"mopsos","kind":"project","path":"projects/mopsos.md"}',
        },
      ],
    });
    expect(lastResult(provider, 2), 'ok');
    expect(
      File(p.join(box.root, 'projects', 'mopsos.md')).readAsStringSync(),
      contains('Weekly hit rate.'),
    );
  });

  test('tool errors and bad arguments are reported, not raised', () async {
    final provider = ScriptedProvider([
      const AgentResponse([
        {
          'type': 'tool_use',
          'id': 't1',
          'name': 'read_note',
          'input': {'__raw': '{oops'},
        },
      ], 'tool_use'),
      toolUse('read_note', 't2', {'slug': 'nope'}),
      text('Sorry.'),
    ]);
    expect(await Agent(provider, box, today: today).ask('read it'), 'Sorry.');
    expect(lastResult(provider, 1), 'Error: the tool arguments were not valid JSON: {oops');
    expect(lastResult(provider, 2), "Error: no note with slug 'nope'.");
  });

  test('only text and tool_use blocks enter the history', () async {
    final provider = ScriptedProvider([
      const AgentResponse([
        {'type': 'thinking'},
        {'type': 'text', 'text': 'hi'},
      ], 'end_turn'),
    ]);
    final agent = Agent(provider, box, today: today);
    expect(await agent.ask('x'), 'hi');
    expect(agent.messages.last['content'], [
      {'type': 'text', 'text': 'hi'},
    ]);
  });

  test('an empty answer leaves a marker and the history consistent', () async {
    final provider = ScriptedProvider([const AgentResponse([], 'end_turn'), text('now')]);
    final agent = Agent(provider, box, today: today);
    expect(await agent.ask('x'), '');
    expect(agent.messages.last['content'], [
      {'type': 'text', 'text': '[no answer]'},
    ]);
    expect(await agent.ask('again'), 'now');
    expect(agent.messages.map((m) => m['role']), ['user', 'assistant', 'user', 'assistant']);
  });

  test('a runaway tool loop is cut off', () async {
    final provider = ScriptedProvider([for (var i = 0; i < 5; i++) toolUse('list_notes', 't$i')]);
    final agent = Agent(provider, box, today: today, maxTurns: 3);
    final answer = await agent.ask('loop');
    expect(answer, contains('stopped'));
    expect(provider.turns, hasLength(3));
    expect(agent.messages.last, {
      'role': 'assistant',
      'content': [
        {'type': 'text', 'text': answer},
      ],
    });
    final roles = agent.messages.map((m) => m['role']).toList();
    for (var i = 1; i < roles.length; i++) {
      expect(roles[i], isNot(roles[i - 1])); // roles alternate
    }
  });

  test('the system prompt states the rules', () {
    final prompt = systemPrompt(today);
    for (final rule in ['get_decision', 'language', 'ask', 'archive', '2026-09-30']) {
      expect(prompt, contains(rule));
    }
    expect(systemPrompt(), isNot(contains('{today}')));
  });

  test('a tool_use outside a tool_use stop is dropped so the history stays valid', () async {
    final provider = ScriptedProvider([
      const AgentResponse([
        {'type': 'text', 'text': 'partial'},
        {
          'type': 'tool_use',
          'id': 't1',
          'name': 'create_note',
          'input': {'kind': 'pro'},
        },
        {'type': 'text', 'text': '[The model stopped early: max_tokens.]'},
      ], 'end_turn'),
      text('fine'),
    ]);
    final agent = Agent(provider, box, today: today);
    expect(await agent.ask('x'), 'partial\n[The model stopped early: max_tokens.]');
    final blocks = [
      for (final m in agent.messages)
        if (m['content'] case final List<Object?> content) ...content,
    ];
    expect(blocks.where((b) => (b! as Map)['type'] == 'tool_use'), isEmpty);
    expect(Directory(p.join(box.root, 'projects')).existsSync(), isFalse); // never ran
    expect(await agent.ask('again'), 'fine');
  });

  test('non-object tool input is an error', () async {
    final provider = ScriptedProvider([
      const AgentResponse([
        {
          'type': 'tool_use',
          'id': 't1',
          'name': 'list_notes',
          'input': ['not', 'a', 'dict'],
        },
      ], 'tool_use'),
      text('ok'),
    ]);
    await Agent(provider, box, today: today).ask('x');
    expect(lastResult(provider, 1), 'Error: the tool arguments must be a JSON object.');
  });

  test('missing tool input means no arguments', () async {
    final provider = ScriptedProvider([
      const AgentResponse([
        {'type': 'tool_use', 'id': 't1', 'name': 'list_notes'},
      ], 'tool_use'),
      text('ok'),
    ]);
    await Agent(provider, box, today: today).ask('x');
    expect(lastResult(provider, 1), '[]');
  });
}

/// Fails on its first turn, then answers.
class FlakyProvider extends ScriptedProvider {
  FlakyProvider(super.responses);

  var failed = false;

  @override
  Future<AgentResponse> turn(String system, List<Message> messages, List<Tool> tools) {
    if (!failed) {
      failed = true;
      throw const NetworkError('offline');
    }
    return super.turn(system, messages, tools);
  }
}

void failureTests() {
  test('a provider failure rolls the turn back so roles keep alternating', () async {
    final box = newBox();
    final provider = FlakyProvider([text('back online')]);
    final agent = Agent(provider, box, today: today);
    await expectLater(agent.ask('first'), throwsA(isA<NetworkError>()));
    expect(agent.messages, isEmpty);
    expect(await agent.ask('second'), 'back online');
    expect(provider.turns.single.$2, [
      {'role': 'user', 'content': 'second'},
    ]);
  });
}
