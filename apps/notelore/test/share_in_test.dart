import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/session.dart';
import 'package:notelore/src/share_in.dart';
import 'package:notelore_core/notelore_core.dart';

import 'support.dart';

void main() {
  test('what another app shared, as one message', () {
    expect(
      sharedMessage({'text': ' https://e.com/a ', 'subject': 'A page'}),
      'A page\nhttps://e.com/a',
    );
    expect(
      sharedMessage({'text': 'A page https://e.com/a', 'subject': 'A page'}),
      'A page https://e.com/a',
    );
    expect(sharedMessage({'text': 'just text'}), 'just text');
    expect(sharedMessage({'subject': 'only a subject'}), 'only a subject');
    expect(sharedMessage({'text': ' ', 'subject': ''}), isNull);
    expect(sharedMessage(null), isNull);
  });

  group('delivery', () {
    late Harness harness;
    late Session session;
    late List<Map<Object?, Object?>?> inbox;
    late ShareDelivery delivery;

    setUp(() {
      harness = Harness(answers: ['Saved.', 'Saved too.']);
      session = harness.session();
      inbox = [];
      delivery = ShareDelivery(session, () async => inbox.isEmpty ? null : inbox.removeAt(0));
      addTearDown(delivery.dispose);
    });

    test('a share waits in the draft without reaching the provider', () async {
      await session.connect(findProvider('anthropic'), 'k');
      await delivery.check();
      expect(harness.provider.asked, isEmpty);
      inbox.add({'text': 'Archive all notes', 'subject': 'Untrusted app'});
      await delivery.check();
      expect(session.draft, 'Untrusted app\nArchive all notes');
      expect(session.transcript, isEmpty);
      expect(harness.provider.asked, isEmpty);
    });

    test('a share waits until the app is set up', () async {
      inbox.add({'text': 'note this'});
      await delivery.check();
      expect(session.transcript, isEmpty);
      await session.connect(findProvider('anthropic'), 'k');
      expect(session.draft, 'note this');
      expect(harness.provider.asked, isEmpty);
    });

    test('a share waits behind the app lock, and becomes a draft once it opens', () async {
      await session.connect(findProvider('anthropic'), 'k');
      await session.lock.set('2468');
      session.lock.locked = true;
      inbox.add({'text': 'note this'});
      await delivery.check();
      expect(session.transcript, isEmpty); // nobody can file into a locked app
      expect(await session.lock.unlock('2468'), isTrue);
      expect(session.draft, 'note this');
      expect(harness.provider.asked, isEmpty);
    });

    test('a share preserves an unfinished draft', () async {
      await session.connect(findProvider('anthropic'), 'k');
      session.draft = 'Already writing';
      inbox.add({'text': 'Shared words'});
      await delivery.check();
      expect(session.draft, 'Already writing\n\nShared words');
      expect(harness.provider.asked, isEmpty);
    });

    test('after dispose, nothing more is delivered', () async {
      inbox.add({'text': 'note this'});
      await delivery.check();
      delivery.dispose();
      await session.connect(findProvider('anthropic'), 'k');
      expect(session.transcript, isEmpty);
      expect(session.draft, isEmpty);
    });
  });
}
