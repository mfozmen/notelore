import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/reminder_notifier.dart';
import 'package:notelore_core/notelore_core.dart';

import 'support.dart';

DueReminder due(int id) => DueReminder(id, DateTime(2099, 1, id), 'Health', 'r$id');

void main() {
  test('exactly the coming reminders are scheduled: none twice, none left over (#431)', () async {
    final device = FakeReminders()..pending.addAll({1: 'old', 2: 'r2'});
    await scheduleReminders(device, [due(2), due(3)]);
    expect(device.pending.keys, unorderedEquals([2, 3]));
    expect(device.cancelled, [1]); // no longer in any note
    expect(device.scheduled.map((r) => r.id), [3]); // 2 was already there
    // The same notes again: nothing changes.
    await scheduleReminders(device, [due(2), due(3)]);
    expect(device.cancelled, [1]);
    expect(device.scheduled.map((r) => r.id), [3]);
  });
}
