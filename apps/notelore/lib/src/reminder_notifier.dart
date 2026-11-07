/// The device's own notifications for the reminders in the notes (#431):
/// an Android alarm, a Windows toast, a macOS notification, at a reminder's
/// time. The notes are the only record; this keeps the device's schedule
/// equal to them.
library;

import 'dart:convert';

import 'package:notelore_core/notelore_core.dart';

/// What a reminder notification's Done and Snooze 1 hour need (#801): the
/// notes folder they act on, and their labels in the user's language.
typedef ReminderActions = ({String notes, String done, String snooze});

const doneAction = 'done';
const snoozeAction = 'snooze';

/// What the device can do with a reminder; a fake in tests.
abstract interface class ReminderNotifier {
  /// Whether Notelore may show notifications now.
  Future<bool> isAllowed();

  /// Asks the user; whether they allowed it.
  Future<bool> ask();

  /// The ids of the reminders scheduled now.
  Future<Set<int>> ids();

  Future<void> schedule(DueReminder reminder, ReminderActions actions);
  Future<void> cancel(int id);
}

/// Schedules exactly [due]: a reminder already scheduled stays as it is, one
/// no note has any more is cancelled, so processing the notes again never
/// doubles a notification. [anew] replaces them all, for when their words
/// change but not what they are (the app lock hides or shows them).
Future<void> scheduleReminders(
  ReminderNotifier device,
  List<DueReminder> due,
  ReminderActions actions, {
  bool anew = false,
}) async {
  final scheduled = anew ? <int>{} : await device.ids();
  if (anew) {
    for (final id in await device.ids()) {
      await device.cancel(id);
    }
  }
  final wanted = {for (final reminder in due) reminder.id};
  for (final id in scheduled.difference(wanted)) {
    await device.cancel(id);
  }
  for (final reminder in due.where((r) => !scheduled.contains(r.id))) {
    await device.schedule(reminder, actions);
  }
}

/// What a notification carries for its actions: no more than it shows, so a
/// snoozed one shows the same words, hidden ones while the app lock is on.
String reminderPayload(DueReminder reminder, ReminderActions actions) => jsonEncode({
  'id': reminder.id,
  'notes': actions.notes,
  'note': reminder.note,
  'text': reminder.text,
  'done': actions.done,
  'snooze': actions.snooze,
});

/// What a Windows toast's button hands back: the payload with its [action],
/// since Windows returns nothing else.
String actionArguments(String payload, String action) =>
    jsonEncode({...jsonDecode(payload) as Map<String, Object?>, 'action': action});

/// A notification's [action] (#801), with the [payload] it was scheduled
/// with (or a Windows button's [actionArguments], which name the action); in
/// the background on Android, where the app may not be running.
/// Edits the note through the store, no model, so it syncs like any edit. A
/// tap on the notification itself, or a reminder no note has any more,
/// changes nothing.
Future<void> actOnReminder(
  ReminderNotifier device,
  String? action,
  String? payload, {
  required DateTime now,
}) async {
  if (payload == null) return;
  final carried = jsonDecode(payload) as Map<String, Object?>;
  final id = carried['id']! as int;
  final notes = carried['notes']! as String;
  switch (carried['action'] ?? action) {
    case doneAction:
      reminderDone(notes, id, now: now);
    case snoozeAction:
      if (snoozeReminder(notes, id, now: now) case final moved?) {
        await device.schedule(
          DueReminder(moved.id, moved.at, carried['note']! as String, carried['text']! as String),
          (notes: notes, done: carried['done']! as String, snooze: carried['snooze']! as String),
        );
      }
  }
}
