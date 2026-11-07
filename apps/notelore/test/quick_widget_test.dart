import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/quick_widget.dart';
import 'package:notelore/src/session.dart';
import 'package:notelore_core/notelore_core.dart';

import 'support.dart';

void main() {
  test('a tap on the widget, read from its link', () {
    expect(QuickOpen.parse('notelore-widget://write'), QuickOpen.write);
    expect(QuickOpen.parse('notelore-widget://talk'), QuickOpen.talk);
    expect({
      QuickOpen.write,
      QuickOpen.talk,
      QuickOpen.parse('notelore-widget://write'),
    }, hasLength(2));
    expect(
      QuickOpen.parse('notelore-widget://note/project/ev-tadilati'),
      const QuickOpen.note('project', 'ev-tadilati'),
    );
    // Any app may start the activity: only what the widget itself sends counts.
    for (final link in [
      null,
      '',
      'https://e.com/write',
      'notelore-widget://delete',
      'notelore-widget://note/secret/x',
      'notelore-widget://note/topic/../../etc',
      'notelore-widget://note/topic',
    ]) {
      expect(QuickOpen.parse(link), isNull, reason: '$link');
    }
  });

  group('with a session', () {
    late Harness harness;
    late Session session;
    final today = DateTime(2026, 11, 7);

    setUp(() {
      harness = Harness(answers: ['Saved.']);
      session = harness.session();
    });

    test('the widget shows the two notes changed last and opens them', () {
      final notes = harness.paths.notes.path;
      createNote(notes, 'topic', 'Kitaplar', today: DateTime(2026, 11, 1));
      createNote(notes, 'project', 'Project Atlas', today: DateTime(2026, 11, 3));
      createNote(notes, 'project', 'Doğum günü', today: DateTime(2026, 11, 2));
      final data = widgetData(session, today);
      expect(data['hint'], session.strings.quickAdd);
      expect(data['talk'], session.strings.talk);
      expect(data['notes'], [
        {
          'title': 'Project Atlas',
          'date': '3 Nov',
          'open': 'notelore-widget://note/project/project-atlas',
        },
        {
          'title': 'Doğum günü',
          'date': '2 Nov',
          'open': 'notelore-widget://note/project/dogum-gunu',
        },
      ]);
      for (final note in data['notes']! as List) {
        expect(QuickOpen.parse((note as Map)['open'] as String), isNotNull);
      }
    });

    test('with the app lock on, the home screen shows no note titles', () async {
      createNote(harness.paths.notes.path, 'project', 'Secret plan', today: today);
      expect(widgetData(session, today)['notes'], hasLength(1));
      await session.lock.set('2468');
      expect(widgetData(session, today)['notes'], isEmpty);
    });

    test('the widget is drawn again when a turn or a sync ends, not on every change', () async {
      final drawn = <Map<String, Object>>[];
      final delivery = QuickDelivery(session, () async => null, draw: drawn.add);
      addTearDown(delivery.dispose);
      await session.connect(findProvider('anthropic'), 'k');
      drawn.clear();
      final turn = session.send('Kitaplar listesine ekle');
      expect(session.busy, isTrue);
      await turn;
      expect(drawn, hasLength(1));
      session.draft = 'typing';
      session.openQuick(QuickOpen.write);
      expect(drawn, hasLength(1));
      delivery.redraw();
      expect(drawn, hasLength(2));
      expect(drawn.last['hint'], session.strings.quickAdd);
      // Turning the lock on takes the titles off the home screen at once.
      await session.lock.set('2468');
      expect(drawn, hasLength(3));
      expect(drawn.last['notes'], isEmpty);
    });

    test('the sync state, only once Drive is connected', () {
      final s = session.strings;
      expect(widgetData(session, today)['sync'], '');
      session.driveConnected = true;
      expect(widgetData(session, today)['sync'], s.syncNever);
      session.lastSynced = DateTime.utc(2026, 11, 7);
      expect(widgetData(session, today)['sync'], s.syncedShort);
      session.syncFailed = true;
      expect(widgetData(session, today)['sync'], s.syncFailed);
      expect(widgetData(session, today)['notes'], isEmpty);
      // A note written elsewhere without a date shows none.
      final raw = File(createNote(harness.paths.notes.path, 'project', 'Raw', today: today));
      raw.writeAsStringSync(
        raw.readAsStringSync().replaceFirst(RegExp(r'updated: .*'), 'updated: soon'),
      );
      session.index.markChanged(raw.path);
      expect((widgetData(session, today)['notes']! as List).single, containsPair('date', ''));
    });

    test('a tap waits until the app is set up and unlocked, then reaches the session', () async {
      final taps = <String?>['notelore-widget://talk'];
      final delivery = QuickDelivery(session, () async => taps.isEmpty ? null : taps.removeAt(0));
      addTearDown(delivery.dispose);
      await delivery.check();
      expect(session.quickOpen, isNull);
      await session.connect(findProvider('anthropic'), 'k');
      expect(session.quickOpen, QuickOpen.talk);
      session.quickOpen = null; // the chat took it
      await session.lock.set('2468');
      session.lock.locked = true;
      taps.add('notelore-widget://note/topic/kitaplar');
      await delivery.check();
      expect(session.quickOpen, isNull);
      expect(await session.lock.unlock('2468'), isTrue);
      expect(session.quickOpen, const QuickOpen.note('topic', 'kitaplar'));
      expect(harness.provider.asked, isEmpty);
      session.quickOpen = null;
      taps.add('https://e.com/write');
      await delivery.check();
      expect(session.quickOpen, isNull);
    });
  });
}
