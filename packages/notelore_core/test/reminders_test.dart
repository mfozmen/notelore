import 'dart:io';

import 'package:notelore_core/src/reminders.dart';
import 'package:notelore_core/src/store/notes.dart';
import 'package:notelore_core/src/store/stale.dart';
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

  test('a reminder keeps its end, and a match gets a realistic one (#535)', () {
    final sport = createNote(root, 'topic', 'Sport', today: d(2026, 10, 1));
    addReminder(sport, 'Football match', d(2026, 10, 20), time: '20:00', today: d(2026, 10, 1));
    addReminder(
      sport,
      'Dinner',
      d(2026, 10, 21),
      time: '19:00',
      end: '21:30',
      today: d(2026, 10, 1),
    );
    final due = upcomingReminders(root, now: now);
    expect(due.firstWhere((r) => r.text == 'Football match').end, DateTime(2026, 10, 20, 22));
    expect(due.firstWhere((r) => r.text == 'Dinner').end, DateTime(2026, 10, 21, 21, 30));
    final items = calendarItems(root, today: DateTime(2026, 10, 19));
    final match = items.firstWhere((i) => i.text == 'Football match');
    expect(match.day, DateTime(2026, 10, 20));
    expect(match.time, '20:00-22:00');
  });

  test('a monthly reminder comes every month, skipping a day that month lacks (#536)', () {
    final monthly = createNote(root, 'topic', 'Monthly', today: d(2026, 10, 1));
    addReminder(
      monthly,
      'Rent',
      d(2026, 10, 18),
      time: '09:00',
      monthly: true,
      today: d(2026, 10, 1),
    );
    addReminder(
      monthly,
      'Last day',
      d(2027, 1, 31),
      time: '09:00',
      monthly: true,
      today: d(2026, 10, 1),
    );
    final due = upcomingReminders(root, now: now).where((r) => r.note == 'Monthly').toList();
    final rent = due.where((r) => r.text == 'Rent').toList();
    expect(rent.map((r) => r.at).take(3), [
      DateTime(2026, 11, 18, 9),
      DateTime(2026, 12, 18, 9),
      DateTime(2027, 1, 18, 9),
    ]);
    expect(rent.map((r) => r.id).toSet(), hasLength(12));
    final last = upcomingReminders(
      root,
      now: DateTime(2027, 1, 31, 10),
    ).where((r) => r.text == 'Last day').map((r) => r.at).take(3);
    expect(last, [DateTime(2027, 3, 31, 9), DateTime(2027, 5, 31, 9), DateTime(2027, 7, 31, 9)]);
    addReminder(monthly, 'Past', d(2026, 10, 1), time: '10:00', today: d(2026, 10, 1));
    final future = calendarItems(
      root,
      today: DateTime(2026, 10, 19),
    ).where((i) => i.text == 'Rent').toList();
    expect(future, hasLength(12));
    expect(future.first.day, DateTime(2026, 11, 18));
    expect(future.last.day, DateTime(2027, 10, 18));
    expect(
      calendarItems(root, today: DateTime(2026, 10, 19)).where((i) => i.text == 'Past'),
      isEmpty,
    );
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

  test('the calendar: reminders from today on and every open todo, by day (#453)', () {
    final shed = p.join(root, 'projects', 'garden-shed.md');
    addTodo(shed, 'Paint the door', due: d(2026, 10, 25), today: d(2026, 10, 1));
    addTodo(shed, 'Late one', due: d(2026, 10, 10), today: d(2026, 10, 1));
    addTodo(shed, 'Done one', due: d(2026, 10, 22), today: d(2026, 10, 1));
    completeTodo(shed, 3, today: d(2026, 10, 2));
    final items = calendarItems(root, today: DateTime(2026, 10, 19));
    expect(items.map((i) => (i.day, i.time, i.text, i.note, i.todo)), [
      (DateTime(2026, 10, 10), null, 'Late one', 'Garden Shed', true),
      // "Gone by" earlier today still shows: the calendar is by day.
      (DateTime(2026, 10, 19), '13:59', 'Gone by', 'Health', false),
      (DateTime(2026, 10, 19), '14:30', 'Later today', 'Health', false),
      (DateTime(2026, 10, 20), '10:00', 'Dentist', 'Health', false),
      (DateTime(2026, 10, 21), null, 'Order the timber', 'Garden Shed', false),
      (DateTime(2026, 10, 25), null, 'Paint the door', 'Garden Shed', true),
    ]);
    // Where it lives, to open it.
    expect((items.first.kind, items.first.slug), ('project', 'garden-shed'));
  });

  group('a notification\'s actions (#801)', () {
    int idOf(String text, {DateTime? at}) =>
        upcomingReminders(root, now: at ?? now).firstWhere((r) => r.text == text).id;
    String health() => File(p.join(root, 'topics', 'health.md')).readAsStringSync();
    String healthPath() => p.join(root, 'topics', 'health.md');
    final pressed = DateTime(2026, 10, 19, 14, 31, 40);

    test('Snooze 1 hour moves the reminder an hour on, keeping its length', () {
      addReminder(
        healthPath(),
        'Team meeting',
        d(2026, 10, 19),
        time: '14:30',
        today: d(2026, 10, 1),
      );
      final id = idOf('Team meeting');
      final moved = snoozeReminder(root, id, now: pressed, today: d(2026, 10, 19))!;
      expect(health(), contains('- 2026-10-19 15:31-16:31: Team meeting\n'));
      expect(health(), isNot(contains('14:30-15:30: Team meeting')));
      // What the device schedules is what the notes now say, under the same id.
      final due = upcomingReminders(root, now: pressed).firstWhere((r) => r.text == 'Team meeting');
      expect(
        (moved.id, moved.at, moved.note, moved.text),
        (due.id, due.at, 'Health', 'Team meeting'),
      );
    });

    test('snoozing a monthly reminder keeps the series and adds this once', () {
      addReminder(
        healthPath(),
        'Rent',
        d(2026, 9, 19),
        time: '14:30',
        monthly: true,
        today: d(2026, 9, 1),
      );
      final id = idOf('Rent', at: DateTime(2026, 10, 19, 14));
      final moved = snoozeReminder(root, id, now: pressed, today: d(2026, 10, 19))!;
      expect(health(), contains('- 2026-09-19 14:30 (monthly): Rent\n'));
      expect(health(), contains('- 2026-10-19 15:31: Rent\n'));
      expect(moved.at, DateTime(2026, 10, 19, 15, 31));
    });

    test('Done ticks the open todo the reminder is about, and only that', () {
      addTodo(healthPath(), 'Call the clinic', today: d(2026, 10, 1));
      addTodo(healthPath(), 'later  TODAY', today: d(2026, 10, 1));
      final id = idOf('Later today');
      expect(reminderDone(root, id, now: pressed, today: d(2026, 10, 19)), isTrue);
      expect(health(), contains('- [ ] 2026-10-01: Call the clinic'));
      expect(health(), contains('- [x] 2026-10-01: later  TODAY'));
      expect(health(), contains('- 2026-10-19 14:30: Later today')); // the reminder stays
    });

    test('Done on a reminder without an open todo changes nothing: it has rung', () {
      addTodo(healthPath(), 'Later today', today: d(2026, 10, 1));
      completeTodo(healthPath(), 1, today: d(2026, 10, 1));
      final before = health();
      expect(reminderDone(root, idOf('Later today'), now: pressed), isFalse);
      expect(health(), before);
    });

    test('a reminder edited or synced away since it rang is left alone', () {
      final before = health();
      expect(snoozeReminder(root, 12345, now: pressed), isNull);
      expect(reminderDone(root, 12345, now: pressed), isFalse);
      expect(health(), before);
    });
  });

  test('the week looked back on: decisions that stand, todos done, todos late (#804)', () {
    final shed = p.join(root, 'projects', 'garden-shed.md');
    recordDecision(shed, 'roof', 'Tin', today: d(2026, 10, 18));
    recordDecision(shed, 'wood', 'Pine', today: d(2026, 10, 20));
    recordDecision(shed, 'wood', 'Oak', reason: 'Lasts longer', today: d(2026, 10, 22));
    addTodo(shed, 'Late one', due: d(2026, 10, 10), today: d(2026, 10, 1));
    addTodo(shed, 'Done this week', due: d(2026, 10, 21), today: d(2026, 10, 1));
    addTodo(shed, 'Done before', due: d(2026, 10, 12), today: d(2026, 10, 1));
    addTodo(shed, 'Due today', due: d(2026, 10, 25), today: d(2026, 10, 1));
    completeTodo(shed, 2, today: d(2026, 10, 21));
    completeTodo(shed, 3, today: d(2026, 10, 12));
    final week = weekItems(root, today: DateTime(2026, 10, 25, 9));
    expect(week.decided.map((i) => (i.day, i.text, i.note, i.todo)), [
      (DateTime(2026, 10, 22), 'wood: Oak', 'Garden Shed', false),
    ]);
    expect(week.done.map((i) => (i.day, i.text, i.number)), [
      (DateTime(2026, 10, 21), 'Done this week', 2),
    ]);
    expect(week.overdue.map((i) => (i.day, i.text)), [(DateTime(2026, 10, 10), 'Late one')]);
    expect((week.overdue.first.kind, week.overdue.first.slug), ('project', 'garden-shed'));
  });

  test(
    'a todo without a date has no day: not in the calendar or the week, still counted (#901)',
    () {
      final shed = p.join(root, 'projects', 'garden-shed.md');
      final text = File(shed).readAsStringSync();
      File(shed).writeAsStringSync(text.replaceFirst('## Todo\n', '## Todo\n- [ ] Buy screws\n'));
      addTodo(shed, 'Late one', due: d(2026, 10, 10), today: d(2026, 10, 1));
      final todos = calendarItems(root, today: DateTime(2026, 10, 19)).where((i) => i.todo);
      expect(todos.map((i) => (i.text, i.number)), [('Late one', 2)]);
      final week = weekItems(root, today: DateTime(2026, 10, 25, 9));
      expect(week.overdue.map((i) => (i.text, i.number)), [('Late one', 2)]);
      final stale = findStaleNotes(root, today: d(2026, 10, 19)).where((s) => s.section == 'todo');
      expect(stale.map((s) => s.number), [2]);
    },
  );
}
