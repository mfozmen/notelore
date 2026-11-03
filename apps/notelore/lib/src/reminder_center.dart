/// The notes' reminders as this device's notifications (#431) and as Google
/// Calendar events (#432), split out of [Session] (#659), which forwards what
/// the screens use and lends what it owns through the callbacks below.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:notelore_core/notelore_core.dart';

import 'reminder_notifier.dart';

enum CalendarProblem { signIn, update, revoked }

class ReminderCenter extends ChangeNotifier {
  ReminderCenter({
    required this.root,
    required this.reminders,
    required this.calendarAuth,
    required this.calendarFor,
    required this.clock,
    required this.offThread,
    required this.isPrivate,
    required this.hiddenText,
    required this.save,
    required this.share,
  });

  /// The notes folder the reminders are read from.
  final String root;

  /// This device's notifications for the notes' reminders (#431); none where
  /// the platform has none (and in tests that do not ask for them).
  final ReminderNotifier? reminders;
  final OAuthSignIn? calendarAuth;
  final ReminderCalendar Function(OAuthSignIn auth) calendarFor;
  final DateTime Function() clock;
  final Future<R> Function<R>(FutureOr<R> Function() work) offThread;

  /// Whether the app lock is on: then nothing of the notes shows.
  final bool Function() isPrivate;

  /// What a reminder says while the lock is on.
  final String Function() hiddenText;

  /// Remembers this device's settings; [share] marks the shared ones changed.
  final void Function() save;
  final void Function() share;

  /// Whether Notelore may notify on this device; null where it cannot at all.
  bool? remindersAllowed;

  /// Google Calendar reminds, on every device, instead of this device's
  /// notifications. Shared through Drive, so no device reminds twice.
  bool calendar = false;

  /// Notelore's own calendar in the user's Google Calendar, shared too.
  String? calendarId;

  /// Calendars this device made before it learned the shared one; removed at
  /// the next calendar sync (#674).
  final dropCalendars = <String>[];

  /// What went wrong with the calendar, for Settings to say in plain words.
  CalendarProblem? calendarProblem;

  /// While the calendar's sign-in or first write runs: the switch waits.
  var calendarBusy = false;

  /// Whether this device holds the calendar grant; null until looked at.
  bool? calendarHere;

  /// A turn here just made a reminder while the calendar is on but this
  /// device has no grant: the app offers the sign-in where it is seen.
  var calendarNudge = false;

  /// The offer was taken or put off; it is not made again on this device.
  var calendarNudged = false;

  /// The reminders of the last pass, to tell one a turn just made; null
  /// before the first.
  Set<int>? _knownDue;

  void calendarNudgeLater() {
    calendarNudge = false;
    calendarNudged = true;
    save();
  }

  /// Asked once a run at most: a refusal is not asked again until Allow.
  var _askedReminders = false;

  /// Whether the scheduled reminders hide their words (the app lock was on);
  /// null until scheduled this run, so the first time schedules them all anew.
  bool? _scheduledPrivately;

  /// The lock turned on or off: the notifications follow (#431).
  void lockChanged() {
    if (_scheduledPrivately case final private? when private != isPrivate()) {
      unawaited(refreshReminders(ask: false));
    }
  }

  /// Another device's calendar setting and id (#674).
  void adopt(bool on, Object? id) {
    calendar = on;
    if (id is String && id != calendarId) {
      // Made here before the shared one arrived: removed at the next calendar
      // sync, so the account keeps one Notelore calendar (#674).
      if (calendarId case final mine?) dropCalendars.add(mine);
      calendarId = id;
    }
    save();
  }

  /// Schedules the notes' coming reminders on this device (#431): at start,
  /// after a turn that wrote notes and after a sync, so the device's schedule
  /// always equals the notes. After a turn (the user just asked for one) it
  /// may [ask] for notifications, once a run. A device that cannot notify
  /// changes nothing else.
  Future<void> refreshReminders({bool ask = true}) => _reminderRuns = _reminderRuns
      .catchError((Object _) {})
      .then((_) => _refreshReminders(ask: ask));

  /// One run at a time: a resume, a sync and a turn can all ask at once; a
  /// run that broke never stops the next.
  Future<void> _reminderRuns = Future.value();

  Future<void> _refreshReminders({required bool ask}) async {
    final now = clock().toLocal();
    // A local, not the field: the closure goes to another isolate, and through
    // `this` it would take this object along, which cannot be sent.
    final notes = root;
    var due = await offThread(() => upcomingReminders(notes, now: now));
    // With the app lock on, nothing of the notes shows: not on a locked
    // phone's screen, not in Google Calendar.
    final private = isPrivate();
    if (private) {
      due = [for (final r in due) DueReminder(r.id, r.at, 'Notelore', hiddenText())];
    }
    final anew = private != _scheduledPrivately;
    _scheduledPrivately = private;
    // Google Calendar reminds where this device holds its grant: this device
    // then none, never twice. Without the grant here (another device turned
    // the calendar on), or in a build that cannot reach it, this device keeps
    // reminding; signed in later, the same pass cancels its own.
    final viaCalendar = calendar && await _holdsCalendar();
    await _remindOnDevice(viaCalendar ? const [] : due, ask: ask, anew: anew);
    // A grant gone on Google's side shows only now: this device, which just
    // cancelled its own, reminds again in this same pass.
    if (viaCalendar && !await _remindInCalendar(due, now)) {
      // It may never have asked for notifications: the calendar reminded until now.
      await _remindOnDevice(due, ask: ask, anew: false);
    }
    final known = _knownDue;
    _knownDue = {for (final r in due) r.id};
    final made = ask && known != null && due.any((r) => !known.contains(r.id));
    // Only while it fits: it goes once the calendar is off or this device holds the grant.
    final revoked = calendarProblem == CalendarProblem.revoked;
    final nudge =
        calendar &&
        calendarHere == false &&
        (calendarNudge || (made || revoked) && !calendarNudged);
    if (nudge != calendarNudge) {
      calendarNudge = nudge;
      notifyListeners();
    }
  }

  /// Whether this device holds the calendar grant, kept in [calendarHere]
  /// for Settings. A keystore that cannot tell keeps what was known, so a
  /// passing error never makes this device remind beside Google; not known
  /// yet, it counts as no grant and this device reminds.
  Future<bool> _holdsCalendar() async {
    final auth = calendarAuth;
    if (auth == null) return false;
    final before = calendarHere;
    try {
      calendarHere = await auth.signedIn();
    } on Exception {
      calendarHere = before ?? false;
    }
    if (calendarHere != before) notifyListeners();
    return calendarHere!;
  }

  Future<void> _remindOnDevice(
    List<DueReminder> due, {
    required bool ask,
    required bool anew,
  }) async {
    final device = reminders;
    if (device == null) return;
    final wasAllowed = remindersAllowed;
    try {
      var allowed = await device.isAllowed();
      if (!allowed && ask && due.isNotEmpty && !_askedReminders) {
        _askedReminders = true;
        allowed = await device.ask();
      }
      remindersAllowed = allowed;
      await scheduleReminders(device, due, anew: anew);
    } on Exception {
      return; // no notifications here: the reminders stay in the notes
    } finally {
      if (remindersAllowed != wasAllowed) notifyListeners(); // Settings shows it
    }
  }

  /// Writes the coming reminders as events in Notelore's calendar; only on a
  /// device that holds the calendar grant.
  /// False when the grant turned out to be gone (revoked on Google's side):
  /// this device then has no grant, and its token is dropped.
  Future<bool> _remindInCalendar(List<DueReminder> due, DateTime now) async {
    final auth = calendarAuth!;
    final before = calendarProblem;
    try {
      final google = calendarFor(auth);
      final id = await google.calendarId(calendarId);
      if (id != calendarId) {
        calendarId = id;
        save();
        share(); // other devices write into the same calendar
      }
      for (final old in [...dropCalendars]) {
        if (old != id) await google.remove(old);
        dropCalendars.remove(old);
        save();
      }
      await google.sync(id, due, now: now);
      calendarProblem = null;
    } on NetworkError {
      return true; // offline: the next refresh catches up
    } on Exception catch (error) {
      // No grant, or still refused after the one refresh: gone, not a passing fault.
      if (error is NotSignedIn || error is HttpError && error.status == 401) {
        return _revoked(auth);
      }
      calendarProblem = CalendarProblem.update; // tried again at the next refresh
    } finally {
      if (calendarProblem != before) notifyListeners();
    }
    return true;
  }

  Future<bool> _revoked(OAuthSignIn auth) async {
    calendarProblem = CalendarProblem.revoked;
    calendarHere = false;
    await _signOutCalendar(auth);
    return false;
  }

  /// Off: the desktop forgets and revokes the calendar's refresh token; a
  /// phone only drops its access token, since the plugin can revoke the whole
  /// account alone, Drive with it. Drive's own grant is never touched.
  Future<void> _signOutCalendar(OAuthSignIn auth) async {
    try {
      await auth.signOut();
    } on Exception {
      return; // offline: the token is gone from this device all the same
    }
  }

  /// Settings' sign-in on a device where the calendar is on (another device
  /// turned it on) but this one has no grant yet.
  Future<void> signInCalendar() async {
    final auth = calendarAuth;
    if (auth == null) return;
    calendarProblem = null;
    try {
      await auth.signIn();
    } on Exception {
      calendarProblem = CalendarProblem.signIn;
      notifyListeners();
      return;
    }
    if (calendarNudge) calendarNudgeLater(); // taken: not offered again
    await refreshReminders(ask: false);
    notifyListeners();
  }

  /// Settings' Add to Google Calendar (#432): on, its own sign-in, then Google
  /// reminds on every device instead of this one; off, the coming events go
  /// and this device reminds again.
  Future<void> setCalendar(bool on) async {
    final auth = calendarAuth;
    if (auth == null || on == calendar || calendarBusy) return;
    calendarProblem = null;
    calendarBusy = true;
    notifyListeners();
    try {
      if (on && !await auth.signedIn()) await auth.signIn();
      if (!on && await auth.signedIn() && calendarId != null) {
        await calendarFor(auth).clear(calendarId!, now: clock().toLocal());
      }
    } on Exception {
      if (on) {
        calendarProblem = CalendarProblem.signIn;
        calendarBusy = false;
        notifyListeners();
        return; // still off: this device keeps reminding
      }
      // Off all the same; the events that could not go stay in that calendar.
    }
    if (!on) await _signOutCalendar(auth);
    calendar = on;
    save();
    share();
    await refreshReminders(ask: false);
    calendarBusy = false;
    notifyListeners();
  }

  /// Settings' Allow: asks for notifications again; whether they are allowed
  /// now. The system may no longer show its question (asked twice already).
  Future<bool> allowReminders() async {
    final device = reminders;
    if (device == null) return false;
    try {
      remindersAllowed = await device.ask();
    } on Exception {
      return false;
    } finally {
      notifyListeners();
    }
    await refreshReminders(ask: false);
    return remindersAllowed ?? false;
  }
}
