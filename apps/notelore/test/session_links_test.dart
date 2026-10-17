import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/session.dart';
import 'package:notelore_core/notelore_core.dart';

import 'support.dart';

void main() {
  test('a link goes to the model with what its page says; the chat shows it as written', () async {
    final harness = Harness(answers: ['Saved to Books.'])
      ..pages['https://example.com/dune'] = '<title>Dune</title><p>A novel by Frank Herbert.</p>';
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    await session.send('for my brother https://example.com/dune');
    final sent = harness.provider.asked.single;
    expect(sent, startsWith('for my brother https://example.com/dune\n\n'));
    expect(
      sent,
      contains('[Page https://example.com/dune ("Dune"):\nDune A novel by Frank Herbert.]'),
    );
    expect(session.transcript.first.text, 'for my brother https://example.com/dune');
    expect(session.transcript.last.text, 'Saved to Books.');
  });

  test('a Stop while the pages load ends the turn before the model is asked', () async {
    final page = Completer<String>();
    final harness = Harness(answers: ['never'])..pages['https://slow.com/'] = page.future;
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    final turn = session.send('https://slow.com/');
    await pumpEventQueue();
    session.stop();
    page.complete('<p>late</p>');
    await turn;
    expect(harness.provider.asked, isEmpty);
    expect(session.transcript.last.role, ChatRole.error);
  });
}
