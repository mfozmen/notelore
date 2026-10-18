import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

/// A note with one reminder far ahead, written as another device would.
void remindIn(Harness harness, String title, String text) {
  final path = createNote(harness.paths.notes.path, 'topic', title, today: today);
  addReminder(path, text, DateTime.utc(2099, 5, 1), time: '10:00', today: today);
}

/// The assistant adds a reminder to Health, then confirms.
List<Object> addsReminder(String text) => [
  AgentResponse([
    {
      'type': 'tool_use',
      'id': 't-$text',
      'name': 'add_reminder',
      'input': {'slug': 'health', 'at': '2099-05-02 09:30', 'text': text},
    },
  ], 'tool_use'),
  'Saved.',
];

void main() {
  test('at start the notes\' reminders are scheduled, without a question (#431)', () async {
    final harness = Harness()..reminders.allowed = false;
    remindIn(harness, 'Health', 'Dentist');
    final session = harness.session();
    await session.load();
    expect(harness.reminders.pending.values, ['Dentist']);
    expect(harness.reminders.scheduled.single.at, DateTime(2099, 5, 1, 10));
    expect(harness.reminders.scheduled.single.note, 'Health');
    // Nothing pops up over the app (or its lock) at start: Settings offers it.
    expect(harness.reminders.asked, 0);
    expect(session.remindersAllowed, isFalse);
  });

  test('a reminder the assistant adds is scheduled; notifications are asked for once', () async {
    final harness = Harness(answers: [...addsReminder('Dentist'), ...addsReminder('Eyes')])
      ..reminders.allowed = false;
    remindIn(harness, 'Health', 'Blood test');
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    await session.send('remind me');
    expect(harness.reminders.pending.values, unorderedEquals(['Blood test', 'Dentist']));
    expect(harness.reminders.asked, 1);
    await session.send('and this');
    expect(harness.reminders.asked, 1); // refused: not asked again this run
    expect(harness.reminders.pending.values, hasLength(3)); // ready for when it is allowed
  });

  test('after a sync, a changed reminder replaces the old one', () async {
    final harness = Harness(auth: FakeAuth());
    remindIn(harness, 'Health', 'Dentist');
    final session = harness.session();
    await session.connectDrive();
    expect(harness.reminders.pending.values, ['Dentist']);
    final path = p.join(harness.paths.notes.path, 'topics', 'health.md');
    File(path).writeAsStringSync(File(path).readAsStringSync().replaceFirst('Dentist', 'Eyes'));
    await session.syncNow();
    expect(harness.reminders.pending.values, ['Eyes']);
    expect(harness.reminders.cancelled, hasLength(1));
  });

  test('Allow asks again; a device that cannot notify never breaks a turn', () async {
    final harness = Harness(answers: ['Saved.'])..reminders.allowed = false;
    final session = harness.session();
    await session.load();
    harness.reminders.grant = true;
    await session.allowReminders();
    expect(session.remindersAllowed, isTrue);
    harness.reminders.fail = PlatformException(code: 'no');
    await session.allowReminders();
    await session.connect(findProvider('anthropic'), 'k');
    await session.send('hi');
    expect(session.transcript.last.text, 'Saved.');
  });

  test('without notifications on this device, nothing to allow', () async {
    final session = Harness().session(reminders: false);
    await session.load();
    expect(session.remindersAllowed, isNull);
    await session.allowReminders();
    await session.refreshReminders();
    expect(session.remindersAllowed, isNull);
  });
}
