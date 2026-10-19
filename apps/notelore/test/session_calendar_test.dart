import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/session.dart';
import 'package:notelore_core/notelore_core.dart';

import 'support.dart';

/// A note with one reminder far ahead.
void remindIn(Harness harness, String title, String text) {
  final path = createNote(harness.paths.notes.path, 'topic', title, today: today);
  addReminder(path, text, DateTime.utc(2099, 5, 1), time: '10:00', today: today);
}

void main() {
  test(
    'Add to Google Calendar: its own sign-in, then Google reminds, not this device (#432)',
    () async {
      final harness = Harness();
      remindIn(harness, 'Health', 'Dentist');
      final session = harness.session();
      await session.load();
      expect(harness.reminders.pending.values, ['Dentist']);
      expect(session.calendarAvailable, isTrue);
      await session.setCalendar(true);
      expect(harness.calendarAuth.granted, isTrue);
      expect(harness.auth?.granted ?? false, isFalse); // Drive's grant is not asked for
      expect(session.calendar, isTrue);
      expect(harness.calendar.events.values, ['Dentist']);
      // Never twice: the device's own notification is cancelled.
      expect(harness.reminders.pending, isEmpty);
      // Remembered on this device.
      final again = harness.session();
      await again.load();
      expect(again.calendar, isTrue);
      expect(harness.calendar.made, 1); // the same calendar, not a new one
    },
  );

  test('while on, a reminder the assistant adds goes to the calendar', () async {
    final harness = Harness(
      answers: [
        const AgentResponse([
          {
            'type': 'tool_use',
            'id': 't1',
            'name': 'create_note',
            'input': {'kind': 'topic', 'title': 'Health'},
          },
          {
            'type': 'tool_use',
            'id': 't2',
            'name': 'add_reminder',
            'input': {'slug': 'health', 'at': '2099-05-02 09:30', 'text': 'Eyes'},
          },
        ], 'tool_use'),
        'Saved.',
      ],
    );
    final session = harness.session();
    await session.setCalendar(true);
    await session.connect(findProvider('anthropic'), 'k');
    await session.send('remind me');
    expect(harness.calendar.events.values, ['Eyes']);
    expect(harness.reminders.pending, isEmpty);
    expect(harness.reminders.asked, 0); // no device permission is needed for Google's
  });

  test('turned off: the coming events go, and this device reminds again', () async {
    final harness = Harness();
    remindIn(harness, 'Health', 'Dentist');
    final session = harness.session();
    await session.load();
    await session.setCalendar(true);
    await session.setCalendar(false);
    expect(harness.calendar.events, isEmpty);
    expect(harness.calendar.cleared, 1);
    expect(harness.reminders.pending.values, ['Dentist']);
    expect(session.calendar, isFalse);
  });

  test('a refused sign-in keeps reminders on this device and says why', () async {
    final harness = Harness()..calendarAuth.failSignIn = const SignInFailed('access_denied');
    final session = harness.session();
    await session.setCalendar(true);
    expect(session.calendar, isFalse);
    expect(session.calendarError, contains('access_denied'));
  });

  test('a calendar error is shown; offline it simply tries again later', () async {
    final harness = Harness();
    remindIn(harness, 'Health', 'Dentist');
    final session = harness.session();
    await session.setCalendar(true);
    harness.calendar.fail = const NetworkError('offline');
    await session.refreshReminders();
    expect(session.calendarError, isNull);
    harness.calendar.fail = const HttpError(403, 'Calendar API has not been used');
    await session.refreshReminders();
    expect(session.calendarError, contains('Calendar API has not been used'));
    harness.calendar.fail = null;
    await session.refreshReminders();
    expect(session.calendarError, isNull);
    expect(harness.calendar.events.values, ['Dentist']);
    // Off while it fails: off all the same; the events wait for the next time.
    harness.calendar.fail = const NetworkError('offline');
    await session.setCalendar(false);
    expect(session.calendar, isFalse);
  });

  test('on from another device: no notification here, and no writes without this grant', () async {
    final harness = Harness(auth: FakeAuth());
    remindIn(harness, 'Health', 'Dentist');
    harness.remote.texts[sharedSettings] = jsonEncode({
      'updated': DateTime.utc(2030).toIso8601String(),
      'calendar': true,
      'calendarId': 'cal-elsewhere',
    });
    final session = harness.session();
    await session.connectDrive();
    expect(session.calendar, isTrue);
    expect(harness.reminders.pending, isEmpty); // Google reminds; this device would twice
    expect(harness.calendar.events, isEmpty); // this device has no calendar grant
    // Granted here too: it writes into the same calendar.
    harness.calendarAuth.granted = true;
    harness.calendar.id = 'cal-elsewhere';
    await session.refreshReminders();
    expect(harness.calendar.made, 0);
    expect(harness.calendar.events.values, ['Dentist']);
  });

  test('the real calendar is Google Calendar', () {
    final session = Session(Harness().paths);
    addTearDown(session.dispose);
    expect(session.calendarFor(FakeAuth()), isA<GoogleCalendar>());
  });

  test('a build without Google sign-in has no switch', () async {
    final session = Harness().session(calendar: false);
    expect(session.calendarAvailable, isFalse);
    await session.setCalendar(true);
    expect(session.calendar, isFalse);
  });
}
