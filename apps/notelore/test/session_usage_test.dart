import 'package:flutter_test/flutter_test.dart';
import 'package:notelore_core/notelore_core.dart';

import 'support.dart';

AgentResponse answer(String text, [TokenUsage? usage]) => AgentResponse(
  [
    {'type': 'text', 'text': text},
  ],
  'end_turn',
  usage: usage,
);

void main() {
  test('every answer adds its tokens to the conversation and to this device (#217)', () async {
    final harness = Harness(answers: [answer('one', const TokenUsage(1000, 100)), answer('two')]);
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'sk-ant-1');
    expect(session.usage.conversation.calls, 0);
    await session.send('first');
    await session.send('second'); // no usage reported
    final talk = session.usage.conversation;
    expect((talk.calls, talk.unreported, talk.input, talk.output), (2, 1, 1000, 100));

    // The device total outlives the app; a new start is a new conversation.
    final again = harness.session();
    await again.load();
    expect(again.usage.device.calls, 2);
    expect(again.usage.conversation.calls, 0);

    await session.logout();
    expect(session.usage.conversation.calls, 0);
    expect(session.usage.device.calls, 2);
  });
}
