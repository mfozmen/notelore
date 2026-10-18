/// The device's own notifications for the reminders in the notes (#431):
/// an Android alarm, a Windows toast, a macOS notification, at a reminder's
/// time. The notes are the only record; this keeps the device's schedule
/// equal to them.
library;

import 'package:notelore_core/notelore_core.dart';

/// What the device can do with a reminder; a fake in tests.
abstract interface class ReminderNotifier {
  /// Whether Notelore may show notifications now.
  Future<bool> isAllowed();

  /// Asks the user; whether they allowed it.
  Future<bool> ask();

  /// The ids of the reminders scheduled now.
  Future<Set<int>> ids();

  Future<void> schedule(DueReminder reminder);
  Future<void> cancel(int id);
}

/// Schedules exactly [due]: a reminder already scheduled stays as it is, one
/// no note has any more is cancelled, so processing the notes again never
/// doubles a notification.
Future<void> scheduleReminders(ReminderNotifier device, List<DueReminder> due) async {
  final scheduled = await device.ids();
  final wanted = {for (final reminder in due) reminder.id};
  for (final id in scheduled.difference(wanted)) {
    await device.cancel(id);
  }
  for (final reminder in due.where((r) => !scheduled.contains(r.id))) {
    await device.schedule(reminder);
  }
}
