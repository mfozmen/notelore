/// The reminders the device should notify of (#431): read from the notes, the
/// one place they live. The app schedules exactly these and cancels any other
/// it scheduled before, so processing the notes again never doubles one.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'store/format.dart';
import 'store/notes.dart';

/// How many coming reminders are scheduled at once, the nearest first: well
/// under what any platform keeps (iOS 64, Android's alarm limit 500).
const maxScheduledReminders = 50;

/// A reminder without a time comes in the morning of its day.
const _morning = 9;

/// One reminder to notify of: at [at] (local), from the note titled [note].
final class DueReminder {
  const DueReminder(this.id, this.at, this.note, this.text, {this.end});

  /// Stable for the same reminder in the same note: the platform's id for it.
  final int id;
  final DateTime at;
  final String note;
  final String text;

  /// When the user gave an end, or the kind of event made one worth keeping.
  final DateTime? end;
}

/// Every reminder in the notes under [root] still to come after [now], the
/// soonest first, at most [maxScheduledReminders]. The archive is left out.
List<DueReminder> upcomingReminders(String root, {required DateTime now}) {
  final due = <DueReminder>[];
  for (final folder in kinds.values) {
    for (final file in markdownFiles(p.join(root, folder))) {
      final note = _readable(file.path);
      if (note == null) continue;
      final rel = p.posix.joinAll(p.split(p.relative(file.path, from: root)));
      due.addAll(_dueFromNote(note, rel, now));
    }
  }
  due.sort((a, b) => a.at.compareTo(b.at));
  return due.take(maxScheduledReminders).toList();
}

List<DueReminder> _dueFromNote(Note note, String rel, DateTime now) {
  final due = <DueReminder>[];
  for (final reminder
      in note.section('reminders')?.entries.whereType<Reminder>() ?? const <Reminder>[]) {
    for (final at in _occurrences(reminder, now)) {
      if (!at.isAfter(now)) continue;
      due.add(_due(reminder, rel, at, note.title));
    }
  }
  return due;
}

DueReminder _due(Reminder reminder, String rel, DateTime at, String note) =>
    DueReminder(_id(reminder, rel, at), at, note, _flat(reminder.text), end: _end(reminder, at));

int _id(Reminder reminder, String rel, DateTime at) =>
    stableId('$rel\n${reminder.render()}${reminder.monthly ? '\n${isoDate(at)}' : ''}');

/// The reminder a notification with [id] rang for, and its note; null when no
/// note has it any more (edited or synced away since). A monthly one's turns
/// of the last two months count, for an action taken late.
({String path, String rel, Note note, Reminder reminder})? _rung(
  String root,
  int id,
  DateTime now,
) {
  final since = now.subtract(const Duration(days: 62));
  for (final folder in kinds.values) {
    for (final file in markdownFiles(p.join(root, folder))) {
      final note = _readable(file.path);
      if (note == null) continue;
      final rel = p.posix.joinAll(p.split(p.relative(file.path, from: root)));
      for (final reminder
          in note.section('reminders')?.entries.whereType<Reminder>() ?? const <Reminder>[]) {
        if (_occurrences(reminder, since).any((at) => _id(reminder, rel, at) == id)) {
          return (path: file.path, rel: rel, note: note, reminder: reminder);
        }
      }
    }
  }
  return null;
}

/// A notification's Snooze 1 hour (#801): the reminder moves to an hour after
/// [now], keeping its length; a monthly one keeps its series and gets this
/// turn once more beside it. The reminder the device should schedule, or null
/// when no note has it any more.
DueReminder? snoozeReminder(String root, int id, {required DateTime now, DateTime? today}) {
  final rung = _rung(root, id, now);
  if (rung == null) return null;
  final (:path, :rel, :note, :reminder) = rung;
  final later = now.add(const Duration(hours: 1));
  final at = DateTime(later.year, later.month, later.day, later.hour, later.minute);
  final start = _at(reminder);
  final end = _end(reminder, start)?.difference(start);
  final moved = Reminder(
    DateTime.utc(at.year, at.month, at.day),
    reminder.text,
    time: _clock(at),
    end: end == null ? null : _clock(at.add(end)),
  );
  moveReminder(path, reminder, moved, keep: reminder.monthly, today: today);
  return _due(moved, rel, at, note.title);
}

/// A notification's Done (#801): ticks the open todo in the same note that
/// says what the reminder says. The reminder itself has rung and stays, so
/// without such a todo nothing changes. True when a todo was ticked.
bool reminderDone(String root, int id, {required DateTime now, DateTime? today}) {
  final rung = _rung(root, id, now);
  if (rung == null) return false;
  final said = _plain(rung.reminder.text);
  final todos = rung.note.section('todo')?.entries.whereType<Todo>() ?? const <Todo>[];
  for (final (i, todo) in todos.indexed) {
    if (!todo.done && _plain(todo.text) == said) {
      completeTodo(rung.path, i + 1, today: today, expect: todo.text);
      return true;
    }
  }
  return false;
}

String _plain(String text) => text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

String _clock(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

/// The note at [path], or null when it is none or cannot be read (not UTF-8,
/// held by another app): the other notes still count.
Note? _readable(String path) {
  try {
    return readNote(path);
  } on NotANote {
    return null;
  } on FileSystemException {
    return null;
  }
}

DateTime _at(Reminder reminder) {
  final [hour, minute] = (reminder.time ?? '$_morning:00').split(':').map(int.parse).toList();
  final day = reminder.date;
  return DateTime(day.year, day.month, day.day, hour, minute);
}

/// The next twelve monthly turns of a monthly reminder, or the one date of a
/// plain one. A month without the day (the 31st in February) is skipped.
Iterable<DateTime> _occurrences(Reminder reminder, DateTime now) sync* {
  final first = _at(reminder);
  if (!reminder.monthly) {
    yield first;
    return;
  }
  var year = first.isAfter(now) ? first.year : now.year;
  var month = first.isAfter(now) ? first.month : now.month;
  var found = 0;
  while (found < 12) {
    final at = DateTime(year, month, first.day, first.hour, first.minute);
    if (_inMonth(at, month) && at.isAfter(now)) {
      yield at;
      found++;
    }
    if (month == 12) {
      month = 1;
      year++;
    } else {
      month++;
    }
  }
}

bool _inMonth(DateTime at, int month) => at.month == month;

DateTime? _end(Reminder reminder, DateTime start) {
  final end = reminder.end;
  if (end == null) return null;
  final [hour, minute] = end.split(':').map(int.parse).toList();
  final at = DateTime(start.year, start.month, start.day, hour, minute);
  return at.isAfter(start) ? at : at.add(const Duration(days: 1));
}

/// FNV-1a over the UTF-8 bytes, kept to 31 bits: a platform's positive int32,
/// the same on every device and run.
int stableId(String key) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(key)) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

/// Continuation lines as one line of text, at most [_longest] characters:
/// a notification is a glance, not the note.
String _flat(String text) {
  final line = text.replaceAll('\n  ', ' ');
  return line.length <= _longest ? line : '${line.substring(0, _longest - 1)}…';
}

const _longest = 200;

/// One thing on a day of the calendar view (#453): a reminder, or an open todo
/// with its date, and the note it lives in.
final class DayItem {
  const DayItem({
    required this.day,
    required this.time,
    required this.text,
    required this.note,
    required this.kind,
    required this.slug,
    required this.todo,
    this.number = 0,
  });

  /// The local date, at midnight.
  final DateTime day;

  /// "HH:MM", or null for the whole day.
  final String? time;
  final String text;

  /// The note's title, and where it lives ([kind], [slug]) to open it.
  final String note;
  final String kind;
  final String slug;
  final bool todo;

  /// For a todo, its number in the note's Todo section (1-based), as
  /// [completeTodo] and [reopenTodo] take it; 0 for a reminder.
  final int number;
}

/// The reminders from [today] on and every open todo under [root], by day and
/// then by time (a whole day first), then by note and text, so the order is
/// the same on every build. Late todos stay: they are still to do.
List<DayItem> calendarItems(String root, {required DateTime today}) {
  final from = DateTime(today.year, today.month, today.day);
  final items = [
    for (final MapEntry(key: kind, value: folder) in kinds.entries)
      for (final file in markdownFiles(p.join(root, folder)))
        if (_readable(file.path) case final note?)
          ..._dayItems(note, kind, p.basenameWithoutExtension(file.path), from),
  ];
  return items..sort(_byDay);
}

/// [note]'s reminders from [from] on and its open todos.
Iterable<DayItem> _dayItems(Note note, String kind, String slug, DateTime from) sync* {
  DayItem item(DateTime date, String? time, String text, {required bool todo, int number = 0}) =>
      DayItem(
        day: DateTime(date.year, date.month, date.day),
        time: time,
        text: _flat(text),
        note: note.title,
        kind: kind,
        slug: slug,
        todo: todo,
        number: number,
      );
  for (final entry in note.section('reminders')?.entries ?? const <NoteEntry>[]) {
    if (entry case final Reminder reminder) {
      yield* _reminderItems(reminder, item, from);
    }
  }
  var number = 0;
  for (final entry in note.section('todo')?.entries ?? const <NoteEntry>[]) {
    if (entry case final Todo todo) {
      number++;
      if (todo case Todo(done: false, :final date?)) {
        yield item(date, null, todo.text, todo: true, number: number);
      }
    }
  }
}

/// The week from Monday to [today] under [root]: the decisions taken in it that
/// still stand, the done todos dated in it, and the open todos dated before
/// [today]. A todo keeps no date of its completion, so "done this week" goes
/// by the todo's own date.
({List<DayItem> decided, List<DayItem> done, List<DayItem> overdue}) weekItems(
  String root, {
  required DateTime today,
}) {
  final day = DateTime(today.year, today.month, today.day);
  final monday = DateTime(day.year, day.month, day.day - (day.weekday - 1));
  bool inWeek(DateTime date) => !date.isBefore(monday) && !date.isAfter(day);
  final notes = _notesUnder(root);
  List<DayItem> sorted(Iterable<DayItem> items) => items.toList()..sort(_byDay);
  return (
    decided: sorted(notes.expand((found) => _standingDecisions(found, inWeek))),
    done: sorted(notes.expand((found) => _todos(found, (t, date) => t.done && inWeek(date)))),
    overdue: sorted(
      notes.expand((found) => _todos(found, (t, date) => !t.done && date.isBefore(day))),
    ),
  );
}

/// A readable note under the notes folder, with its kind and slug.
typedef _Found = ({Note note, String kind, String slug});

List<_Found> _notesUnder(String root) => [
  for (final MapEntry(key: kind, value: folder) in kinds.entries)
    for (final file in markdownFiles(p.join(root, folder)))
      if (_readable(file.path) case final note?)
        (note: note, kind: kind, slug: p.basenameWithoutExtension(file.path)),
];

DayItem _weekItem(_Found found, DateTime date, String text, {required bool todo, int number = 0}) =>
    DayItem(
      day: DateTime(date.year, date.month, date.day),
      time: null,
      text: _flat(text),
      note: found.note.title,
      kind: found.kind,
      slug: found.slug,
      todo: todo,
      number: number,
    );

Iterable<DayItem> _standingDecisions(_Found found, bool Function(DateTime) inWeek) sync* {
  for (final entry in found.note.section('decisions')?.entries ?? const <NoteEntry>[]) {
    if (entry case final Decision d when d.superseded == null && inWeek(d.date)) {
      yield _weekItem(found, d.date, '${d.topic}: ${d.value}', todo: false);
    }
  }
}

/// The todos of [found] that pass [keep], with their number in the section.
Iterable<DayItem> _todos(_Found found, bool Function(Todo, DateTime date) keep) sync* {
  var number = 0;
  for (final entry in found.note.section('todo')?.entries ?? const <NoteEntry>[]) {
    if (entry case final Todo todo) {
      number++;
      if (todo.date case final date? when keep(todo, date)) {
        yield _weekItem(found, date, todo.text, todo: true, number: number);
      }
    }
  }
}

Iterable<DayItem> _reminderItems(
  Reminder reminder,
  DayItem Function(DateTime, String?, String, {required bool todo}) item,
  DateTime from,
) sync* {
  final range = _range(reminder);
  for (final at in _occurrences(reminder, from)) {
    if (!at.isBefore(from)) yield item(at, range, reminder.text, todo: false);
  }
}

String? _range(Reminder reminder) {
  final time = reminder.time;
  if (time == null || reminder.end == null) return time;
  return '$time-${reminder.end}';
}

int _byDay(DayItem a, DayItem b) {
  for (final order in [
    a.day.compareTo(b.day),
    (a.time ?? '').compareTo(b.time ?? ''),
    a.note.compareTo(b.note),
    a.text.compareTo(b.text),
  ]) {
    if (order != 0) return order;
  }
  return 0;
}
