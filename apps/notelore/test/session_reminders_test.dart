import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart' show XFile;

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

  test('with the app lock on, a notification says only that there is a reminder', () async {
    final harness = Harness();
    remindIn(harness, 'Divorce', 'Pay the lawyer');
    final session = harness.session();
    await session.load();
    expect(harness.reminders.scheduled.last.text, 'Pay the lawyer');
    await session.lock.set('2580');
    await pumpEventQueue();
    // On a locked phone's screen nothing of the note shows.
    expect(harness.reminders.pending.values, ['You have a reminder.']);
    expect(harness.reminders.scheduled.last.note, 'Notelore');
    expect(harness.reminders.scheduled.last.at, DateTime(2099, 5, 1, 10)); // still on time
    expect(await session.lock.remove('2580'), isTrue);
    await pumpEventQueue();
    expect(harness.reminders.pending.values, ['Pay the lawyer']);
  });

  test('a deleted note takes its reminder with it; restored, it comes back', () async {
    final harness = Harness();
    remindIn(harness, 'Health', 'Dentist');
    final session = harness.session();
    await session.load();
    final note = session.listNotes().single;
    final archived = await session.deleteNote(note);
    expect(harness.reminders.pending, isEmpty);
    await session.restoreNote(note, archived!);
    expect(harness.reminders.pending.values, ['Dentist']);
    await session.deleteNote(note);
    await session.restoreArchived(session.listArchived().single);
    expect(harness.reminders.pending.values, ['Dentist']);
  });

  test('a shared note brought in brings its reminders', () async {
    final harness = Harness();
    final session = harness.session();
    await session.load();
    final shared = createNote(harness.scratch.path, 'topic', 'Trip', today: today);
    addReminder(shared, 'Pack', DateTime.utc(2099, 6, 1), today: today);
    harness.files.picked = [XFile(shared)];
    await session.importNotes();
    expect(harness.reminders.pending.values, ['Pack']);
  });

  test('a reminder run that broke never stops the next', () async {
    final harness = Harness();
    final session = harness.session();
    harness.reminders.breakOnce = StateError('a bug in a run');
    await expectLater(session.refreshReminders(), throwsStateError);
    remindIn(harness, 'Health', 'Dentist');
    await session.refreshReminders();
    expect(harness.reminders.pending.values, ['Dentist']);
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
