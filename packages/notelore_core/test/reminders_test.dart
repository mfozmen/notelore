import 'dart:io';

import 'package:notelore_core/src/reminders.dart';
import 'package:notelore_core/src/store/notes.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/files.dart';

DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

void main() {
  late String root;
  final now = DateTime(2026, 10, 19, 14);

  setUp(() {
    root = p.join(tempDir(), 'notes');
    final health = createNote(root, 'topic', 'Health', today: d(2026, 10, 1));
    addReminder(health, 'Dentist', d(2026, 10, 20), time: '10:00', today: d(2026, 10, 1));
    addReminder(health, 'Gone by', d(2026, 10, 19), time: '13:59', today: d(2026, 10, 1));
    addReminder(health, 'Later today', d(2026, 10, 19), time: '14:30', today: d(2026, 10, 1));
    final shed = createNote(root, 'project', 'Garden Shed', today: d(2026, 10, 1));
    addReminder(shed, 'Order the timber', d(2026, 10, 21), today: d(2026, 10, 1));
    File(p.join(root, 'topics', 'not-a-note.md')).writeAsStringSync('plain\n');
    final archived = createNote(
      p.join(root, '_archive', '2026-10-01'),
      'topic',
      'Old',
      today: d(2026, 10, 1),
    );
    addReminder(archived, 'Never', d(2026, 12, 1), today: d(2026, 10, 1));
  });

  test('the coming reminders, soonest first, each at its local minute (#431)', () {
    final due = upcomingReminders(root, now: now);
    expect(due.map((r) => (r.text, r.note, r.at)), [
      ('Later today', 'Health', DateTime(2026, 10, 19, 14, 30)),
      ('Dentist', 'Health', DateTime(2026, 10, 20, 10)),
      // No time: in the morning of its day.
      ('Order the timber', 'Garden Shed', DateTime(2026, 10, 21, 9)),
    ]);
  });

  test('an id stays the same for the same reminder and differs for another', () {
    final first = upcomingReminders(root, now: now);
    final again = upcomingReminders(root, now: now);
    expect(again.map((r) => r.id), first.map((r) => r.id));
    expect(first.map((r) => r.id).toSet(), hasLength(3));
    expect(first.every((r) => r.id >= 0 && r.id < 1 << 31), isTrue); // a platform's int32 id
    // Written again elsewhere, the same words on the same day are another reminder.
    final other = createNote(root, 'topic', 'Other', today: d(2026, 10, 1));
    addReminder(other, 'Dentist', d(2026, 10, 20), time: '10:00', today: d(2026, 10, 1));
    final ids = upcomingReminders(root, now: now).map((r) => r.id).toSet();
    expect(ids, hasLength(4));
  });

  test('only the nearest ones, as many as a device schedules', () {
    final many = createNote(root, 'topic', 'Many', today: d(2026, 10, 1));
    for (var i = 1; i <= 70; i++) {
      addReminder(many, 'Day $i', d(2026, 11, 1).add(Duration(days: i)), today: d(2026, 10, 1));
    }
    final due = upcomingReminders(root, now: now);
    expect(due, hasLength(maxScheduledReminders));
    expect(due.first.text, 'Later today');
  });

  test("a long reminder's words are cut for a notification", () {
    final long = createNote(root, 'topic', 'Long', today: d(2026, 10, 1));
    addReminder(long, 'word ' * 100, d(2026, 10, 19), time: '15:00', today: d(2026, 10, 1));
    final text = upcomingReminders(root, now: now).firstWhere((r) => r.note == 'Long').text;
    expect(text.length, 200);
    expect(text, endsWith('…'));
  });

  test('a note that cannot be read is skipped, never the others', () {
    File(p.join(root, 'topics', 'latin1.md')).writeAsBytesSync([0x2d, 0xff, 0xfe, 0x0a]);
    expect(upcomingReminders(root, now: now), hasLength(3));
  });

  test('no notes folder, no reminders', () {
    expect(upcomingReminders(p.join(tempDir(), 'none'), now: now), isEmpty);
  });
}
