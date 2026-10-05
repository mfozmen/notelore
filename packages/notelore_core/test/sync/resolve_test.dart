import 'dart:io';

import 'package:notelore_core/src/providers/base.dart';
import 'package:notelore_core/src/sync/merge.dart';
import 'package:notelore_core/src/sync/resolve.dart';
import 'package:test/test.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

const conflict = Conflict(
  ['- 2026-09-01: meeting on Monday\n'],
  ['- 2026-09-01: meeting on Tuesday\n'],
  ['- 2026-09-01: meeting on Monday at 10:00\n'],
);

/// A model that answers from a script and records what it was asked.
class Scripted {
  Scripted(this.answers);

  final List<Object> answers;
  final calls = <(String, String)>[];

  Future<String> call(String system, String prompt) async {
    calls.add((system, prompt));
    final answer = answers.removeAt(0);
    if (answer is Exception) throw answer;
    return answer as String;
  }
}

void main() {
  providerTests();
  test('the model sees all three versions', () async {
    final model = Scripted([
      '<merged>\n- 2026-09-01: meeting on Tuesday at 10:00\n</merged>\n'
          '<why>The laptop moved the day and the Mac added the time; both kept.</why>',
    ]);
    final resolver = ModelResolver(model.call);
    expect(await resolver(conflict), ['- 2026-09-01: meeting on Tuesday at 10:00\n']);
    final (system, prompt) = model.calls.single;
    for (final line in ['meeting on Monday\n', 'meeting on Tuesday\n', 'Monday at 10:00\n']) {
      expect(prompt, contains(line));
    }
    expect(system.toLowerCase(), contains('never invent'));
    expect(resolver.explanations, [
      'The laptop moved the day and the Mac added the time; both kept.',
    ]);
  });

  test('multiple lines and a missing final newline', () async {
    final resolver = ModelResolver(Scripted(['<merged>\na\nb</merged><why>ok</why>']).call);
    expect(await resolver(conflict), ['a\n', 'b\n']);
  });

  test('an empty merge is allowed and the deletion is visible in the report', () async {
    final resolver = ModelResolver(
      Scripted(['<merged>\n</merged><why>Both sides dropped it.</why>']).call,
    );
    expect(await resolver(conflict), isEmpty);
    expect(resolver.explanations, ['Removed the conflicting lines: Both sides dropped it.']);
  });

  test('an answer without the tags leaves the conflict open', () async {
    final resolver = ModelResolver(Scripted(['I think Tuesday is right.']).call);
    expect(await resolver(conflict), isNull);
    expect(resolver.explanations, isEmpty);
    final noWhy = ModelResolver(Scripted(['<merged>\nx\n</merged>']).call);
    expect(await noWhy(conflict), isNull);
  });

  test('a provider failure leaves the conflict open', () async {
    final resolver = ModelResolver(Scripted([const SocketException('offline')]).call);
    expect(await resolver(conflict), isNull);
  });

  test('model output is NFC', () async {
    final nfd = unorm.nfd('- 2026-09-01: toplantı Salı\n');
    final resolver = ModelResolver(Scripted(['<merged>\n$nfd</merged><why>ok</why>']).call);
    expect(await resolver(conflict), [unorm.nfc(nfd)]);
  });
}

class _OneAnswer implements LlmProvider {
  final calls = <(String, List<Message>, List<Tool>)>[];

  @override
  String get model => 'one';

  @override
  Future<AgentResponse> turn(String system, List<Message> messages, List<Tool> tools) async {
    calls.add((system, messages, tools));
    return const AgentResponse([
      {'type': 'text', 'text': '<merged>\nx\n'},
      {'type': 'tool_use', 'id': 't', 'name': 'n', 'input': <String, Object?>{}},
      {'type': 'text', 'text': '</merged><why>ok</why>'},
    ], 'end_turn');
  }
}

void providerTests() {
  test('a provider plugs in as Ask: one user message, no tools, the texts joined', () async {
    final provider = _OneAnswer();
    expect(await ModelResolver(askProvider(provider)).call(conflict), ['x\n']);
    final (system, messages, tools) = provider.calls.single;
    expect(system, contains('Never invent'));
    expect(messages.single['role'], 'user');
    expect(tools, isEmpty);
  });
}
