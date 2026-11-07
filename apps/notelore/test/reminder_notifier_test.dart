import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/reminder_notifier.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

DueReminder due(int id) => DueReminder(id, DateTime(2099, 1, id), 'Health', 'r$id');

const ReminderActions labels = (notes: 'notes', done: 'Done', snooze: 'Snooze 1 hour');

void main() {
  test('exactly the coming reminders are scheduled: none twice, none left over (#431)', () async {
    final device = FakeReminders()..pending.addAll({1: 'old', 2: 'r2'});
    await scheduleReminders(device, [due(2), due(3)], labels);
    expect(device.pending.keys, unorderedEquals([2, 3]));
    expect(device.cancelled, [1]); // no longer in any note
    expect(device.scheduled.map((r) => r.id), [3]); // 2 was already there
    expect(device.actions, [labels]);
    // The same notes again: nothing changes.
    await scheduleReminders(device, [due(2), due(3)], labels);
    expect(device.cancelled, [1]);
    expect(device.scheduled.map((r) => r.id), [3]);
  });

  group('a notification\'s Done and Snooze 1 hour (#801)', () {
    late String notes;
    late String health;
    final rang = DateTime(2099, 5, 1, 10, 0, 20);

    setUp(() {
      notes = p.join(Directory.systemTemp.createTempSync('notelore_actions_').path, 'notes');
      health = createNote(notes, 'topic', 'Health', today: DateTime.utc(2099, 4, 1));
      addReminder(health, 'Dentist', DateTime.utc(2099, 5, 1), time: '10:00');
      addTodo(health, 'Dentist');
    });

    /// What the device was handed with the notification, and gives back.
    String payload() {
      final dentist = upcomingReminders(notes, now: DateTime(2099, 4, 1)).single;
      // With the app lock on, the words it shows are the hidden ones.
      final shown = DueReminder(dentist.id, dentist.at, 'Notelore', 'You have a reminder.');
      return reminderPayload(shown, (notes: notes, done: 'Bitti', snooze: '1 saat ertele'));
    }

    test('Snooze moves the reminder in its note and schedules it, showing no more', () async {
      final device = FakeReminders();
      await actOnReminder(device, snoozeAction, payload(), now: rang);
      expect(File(health).readAsStringSync(), contains('- 2099-05-01 11:00: Dentist\n'));
      final moved = device.scheduled.single;
      expect(
        (moved.at, moved.note, moved.text),
        (DateTime(2099, 5, 1, 11), 'Notelore', 'You have a reminder.'),
      );
      // The next refresh finds it already scheduled: the same id as the notes give.
      expect(moved.id, upcomingReminders(notes, now: rang).single.id);
      expect(device.actions.single, (notes: notes, done: 'Bitti', snooze: '1 saat ertele'));
    });

    test('Done ticks the todo; no model, nothing scheduled', () async {
      final device = FakeReminders();
      // A Windows button: its arguments name the action.
      await actOnReminder(device, null, actionArguments(payload(), doneAction), now: rang);
      expect(File(health).readAsStringSync(), contains('- [x] '));
      expect(device.scheduled, isEmpty);
    });

    test('a tap on the notification itself, or a reminder gone, changes nothing', () async {
      final device = FakeReminders();
      final before = File(health).readAsStringSync();
      await actOnReminder(device, null, payload(), now: rang);
      await actOnReminder(device, payload(), payload(), now: rang); // a Windows toast's body
      await actOnReminder(device, snoozeAction, null, now: rang);
      final gone = payload().replaceFirst(RegExp(r'"id":\d+'), '"id":7');
      await actOnReminder(device, snoozeAction, gone, now: rang);
      expect(File(health).readAsStringSync(), before);
      expect(device.scheduled, isEmpty);
    });
  });
}
