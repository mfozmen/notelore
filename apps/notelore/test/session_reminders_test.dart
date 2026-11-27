import 'dart:async';
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
    // Its Done and Snooze act on these notes, labelled in the user's language (#801).
    expect(harness.reminders.actions.single, (
      notes: harness.paths.notes.path,
      done: 'Done',
      snooze: 'Snooze 1 hour',
    ));
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

  test('the turn answers while the system still asks about notifications (#941)', () async {
    // macOS kept the reply until its prompt was closed.
    final harness = Harness(answers: addsReminder('Dentist'))
      ..reminders.allowed = false
      ..reminders.grant = true
      ..reminders.answering = Completer()
      ..reminders.refuseUnallowed = true;
    remindIn(harness, 'Health', 'Blood test');
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    await session.send('remind me').timeout(const Duration(seconds: 5));
    expect(harness.reminders.asked, 1);
    expect(harness.reminders.pending, isEmpty); // refused until allowed
    expect(session.remindersAllowed, isFalse);
    harness.reminders.answering!.complete();
    await pumpEventQueue();
    expect(session.remindersAllowed, isTrue);
    expect(harness.reminders.pending.values, unorderedEquals(['Blood test', 'Dentist']));
  });

  test(
    'a system that cannot ask leaves the reminders in the notes, and the turn answers',
    () async {
      final harness = Harness(answers: addsReminder('Dentist'))
        ..reminders.allowed = false
        ..reminders.askFails = PlatformException(code: 'no');
      remindIn(harness, 'Health', 'Blood test');
      final session = harness.session();
      await session.connect(findProvider('anthropic'), 'k');
      await session.send('remind me');
      await pumpEventQueue();
      expect(harness.reminders.asked, 1);
      expect(session.remindersAllowed, isFalse);
      expect(session.transcript.last.text, isNotEmpty);
    },
  );

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
    await pumpEventQueue(); // the reminders follow, the delete does not wait (#504)
    expect(harness.reminders.pending, isEmpty);
    await session.restoreNote(note, archived!);
    await pumpEventQueue();
    expect(harness.reminders.pending.values, ['Dentist']);
    await session.deleteNote(note);
    await session.restoreArchived(session.listArchived().single);
    await pumpEventQueue();
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
    await pumpEventQueue();
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

  group('the morning brief (#918)', () {
    // 09:00 on 30 April: today's 08:00 has passed, so the first brief is tomorrow's.
    DateTime clock() => DateTime(2099, 4, 30, 9);

    Harness withNotes({String language = 'en'}) {
      final harness = Harness();
      remindIn(harness, 'Health', 'Dentist');
      final health = p.join(harness.paths.notes.path, 'topics', 'health.md');
      addTodo(health, 'Pay rent', due: DateTime.utc(2099, 4, 29), today: today);
      return harness;
    }

    List<DueReminder> briefs(Harness harness) => [
      for (final r in harness.reminders.scheduled)
        if (r.brief && harness.reminders.pending.containsKey(r.id)) r,
    ];

    test('off by default; on, a brief each morning of the week at 08:00', () async {
      final harness = withNotes();
      final session = harness.session(clock: clock);
      await session.load();
      expect((session.brief, session.briefAt), (false, 8 * 60));
      expect(harness.reminders.scheduled.where((r) => r.brief), isEmpty);
      await session.setBrief(on: true);
      final week = briefs(harness);
      expect(week.map((r) => r.at), [for (var d = 1; d <= 7; d++) DateTime(2099, 5, d, 8)]);
      expect((week.first.note, week.first.text), ('Today', '10:00 Dentist\nOverdue: Pay rent'));
      expect(week[1].text, 'Overdue: Pay rent');
      // The reminder itself still rings at its own time.
      expect(harness.reminders.pending.values, contains('Dentist'));
    });

    test('a new time moves the briefs, and both persist on this device', () async {
      final harness = withNotes();
      final session = harness.session(clock: clock);
      await session.load();
      await session.setBrief(on: true);
      await session.setBrief(at: 10 * 60);
      // 10:00 has not come yet today: today has one too.
      expect(briefs(harness).map((r) => r.at).first, DateTime(2099, 4, 30, 10));
      expect(briefs(harness), hasLength(7));
      final again = harness.session(clock: clock);
      await again.load();
      expect((again.brief, again.briefAt), (true, 10 * 60));
    });

    test('off cancels every brief; a free week has none', () async {
      final harness = withNotes();
      final session = harness.session(clock: clock);
      await session.load();
      await session.setBrief(on: true);
      await session.setBrief(on: false);
      expect(briefs(harness), isEmpty);
      expect(harness.reminders.pending.values, ['Dentist']);
      final free = Harness();
      final quiet = free.session(clock: clock);
      await quiet.load();
      await quiet.setBrief(on: true);
      expect(free.reminders.scheduled, isEmpty);
    });

    test("in the user's language, and with the app lock on, none of the notes' words", () async {
      final harness = withNotes();
      final session = harness.session(clock: clock, systemLanguage: 'tr');
      await session.load();
      await session.setBrief(on: true);
      expect(
        (briefs(harness).first.note, briefs(harness).first.text),
        ('Bugün', '10:00 Dentist\nGecikmiş: Pay rent'),
      );
      await session.lock.set('2580');
      await pumpEventQueue();
      expect(briefs(harness).first.text, 'Sabah özetin hazır.');
      expect(briefs(harness).first.note, 'Notelore');
    });

    test('a tap on it asks for the calendar on today', () async {
      final harness = withNotes();
      final session = harness.session(clock: clock);
      await session.load();
      var heard = 0;
      session.addListener(() => heard++);
      harness.reminders.openToday!();
      expect((session.calendarToday, heard), (true, 1));
    });
  });
}
