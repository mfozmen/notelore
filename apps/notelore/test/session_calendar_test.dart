import 'dart:async';
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
    // The calendar's grant goes with it; Drive's stays as it was.
    expect(harness.calendarAuth.signedOut, isTrue);
    // Offline when signing out: off all the same.
    await session.setCalendar(true);
    harness.calendarAuth.failSignOut = const NetworkError('offline');
    await session.setCalendar(false);
    expect(session.calendar, isFalse);
  });

  test('with the app lock on, the calendar shows nothing of the notes either', () async {
    final harness = Harness();
    remindIn(harness, 'Divorce', 'Pay the lawyer');
    final session = harness.session();
    await session.load();
    await session.setCalendar(true);
    expect(harness.calendar.events.values, ['Pay the lawyer']);
    await session.lock.set('2580');
    await pumpEventQueue();
    expect(harness.calendar.events.values, ['You have a reminder.']);
    expect(await session.lock.remove('2580'), isTrue);
    await pumpEventQueue();
    expect(harness.calendar.events.values, ['Pay the lawyer']);
  });

  test('busy while it signs in: a second tap starts no second sign-in', () async {
    final harness = Harness();
    final hold = harness.calendarAuth.hold = Completer<void>();
    final session = harness.session();
    final first = session.setCalendar(true);
    await pumpEventQueue();
    expect(session.calendarBusy, isTrue);
    await session.setCalendar(true); // ignored while the first runs
    hold.complete();
    await first;
    expect(session.calendarBusy, isFalse);
    expect(session.calendar, isTrue);
  });

  test('a refused sign-in keeps reminders on this device and says why', () async {
    final harness = Harness()..calendarAuth.failSignIn = const SignInFailed('access_denied');
    final session = harness.session();
    await session.setCalendar(true);
    expect(session.calendar, isFalse);
    expect(session.calendarProblem, CalendarProblem.signIn);
  });

  test('a calendar error is shown; offline it simply tries again later', () async {
    final harness = Harness();
    remindIn(harness, 'Health', 'Dentist');
    final session = harness.session();
    await session.setCalendar(true);
    harness.calendar.fail = const NetworkError('offline');
    await session.refreshReminders();
    expect(session.calendarProblem, isNull);
    harness.calendar.fail = const HttpError(403, 'Calendar API has not been used');
    await session.refreshReminders();
    expect(session.calendarProblem, CalendarProblem.update);
    harness.calendar.fail = null;
    await session.refreshReminders();
    expect(session.calendarProblem, isNull);
    expect(harness.calendar.events.values, ['Dentist']);
    // Off while it fails: off all the same; the events wait for the next time.
    harness.calendar.fail = const NetworkError('offline');
    await session.setCalendar(false);
    expect(session.calendar, isFalse);
  });

  test(
    'on from another device: this device reminds until it signs in here, never twice (#503)',
    () async {
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
      // Without the grant here nothing would reach Google until the other device
      // opens: this one keeps reminding.
      expect(harness.reminders.pending.values, ['Dentist']);
      expect(harness.calendar.events, isEmpty); // this device has no calendar grant
      expect(session.calendarHere, isFalse); // Settings offers the sign-in
      // Signed in here too: it writes into the same calendar, and its own
      // notification goes, so nothing reminds twice.
      harness.calendar.id = 'cal-elsewhere';
      await session.signInCalendar();
      expect(session.calendarHere, isTrue);
      expect(harness.calendar.made, 0);
      expect(harness.calendar.events.values, ['Dentist']);
      expect(harness.reminders.pending, isEmpty);
    },
  );

  test('set up elsewhere, a reminder made here offers the sign-in once (#503)', () async {
    final harness = Harness();
    final session = harness.session();
    await session.load();
    session.calendar = true; // as the shared settings bring it
    await session.refreshReminders();
    expect(session.calendarNudge, isFalse); // nothing to remind of yet
    remindIn(harness, 'Health', 'Dentist');
    await session.refreshReminders(ask: false); // a sync brought it: not made here
    expect(session.calendarNudge, isFalse);
    await session.refreshReminders(); // a turn that made no reminder
    expect(session.calendarNudge, isFalse);
    remindIn(harness, 'Car', 'Tyres');
    await session.refreshReminders(); // after the turn that made it
    expect(session.calendarNudge, isTrue);
    // Meanwhile this device reminds.
    expect(harness.reminders.pending.values, unorderedEquals(['Dentist', 'Tyres']));
    session.calendarNudgeLater();
    expect(session.calendarNudge, isFalse);
    await session.refreshReminders();
    expect(session.calendarNudge, isFalse); // once
    // Remembered: the next start does not ask again.
    final again = harness.session();
    await again.load();
    again.calendar = true;
    await again.refreshReminders();
    expect(again.calendarNudge, isFalse);
  });

  test('signed in from the offer, it is not offered again (#503)', () async {
    final harness = Harness();
    final session = harness.session();
    await session.load();
    session.calendar = true;
    remindIn(harness, 'Health', 'Dentist');
    await session.refreshReminders();
    expect(session.calendarNudge, isTrue);
    await session.signInCalendar();
    expect(session.calendarNudge, isFalse);
    expect(harness.reminders.pending, isEmpty);
    expect(harness.calendar.events.values, ['Dentist']);
  });

  test('a keystore that cannot tell counts as no grant: this device reminds (#503)', () async {
    final harness = Harness();
    remindIn(harness, 'Health', 'Dentist');
    harness.calendarAuth.failSignedIn = Exception('keystore locked');
    final session = harness.session();
    await session.load();
    session.calendar = true;
    await session.refreshReminders();
    expect(session.calendarHere, isFalse);
    expect(harness.reminders.pending.values, ['Dentist']);
  });

  test('a build without Google sign-in keeps reminding, whatever another device chose', () async {
    final harness = Harness();
    remindIn(harness, 'Health', 'Dentist');
    final session = harness.session(calendar: false);
    session.calendar = true; // as the shared settings bring it
    await session.refreshReminders();
    expect(harness.reminders.pending.values, ['Dentist']);
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
    await session.signInCalendar();
    expect(session.calendar, isFalse);
  });

  test("a refused sign-in on a device that is not the calendar's says so", () async {
    final harness = Harness()..calendarAuth.failSignIn = const SignInFailed('access_denied');
    final session = harness.session();
    await session.signInCalendar();
    expect(session.calendarProblem, CalendarProblem.signIn);
  });
}
