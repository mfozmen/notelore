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
  const DueReminder(this.id, this.at, this.note, this.text);

  /// Stable for the same reminder in the same note: the platform's id for it.
  final int id;
  final DateTime at;
  final String note;
  final String text;
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
      for (final reminder
          in note.section('reminders')?.entries.whereType<Reminder>() ?? const <Reminder>[]) {
        final at = _at(reminder);
        if (at.isAfter(now)) {
          due.add(
            DueReminder(
              stableId('$rel\n${reminder.render()}'),
              at,
              note.title,
              _flat(reminder.text),
            ),
          );
        }
      }
    }
  }
  due.sort((a, b) => a.at.compareTo(b.at));
  return due.take(maxScheduledReminders).toList();
}

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
  DayItem item(DateTime date, String? time, String text, {required bool todo}) => DayItem(
    day: DateTime(date.year, date.month, date.day),
    time: time,
    text: _flat(text),
    note: note.title,
    kind: kind,
    slug: slug,
    todo: todo,
  );
  for (final entry in note.section('reminders')?.entries ?? const <NoteEntry>[]) {
    if (entry case Reminder(:final date, :final time, :final text)
        when !DateTime(date.year, date.month, date.day).isBefore(from)) {
      yield item(date, time, text, todo: false);
    }
  }
  for (final entry in note.section('todo')?.entries ?? const <NoteEntry>[]) {
    if (entry case Todo(:final date, :final text, done: false)) {
      yield item(date, null, text, todo: true);
    }
  }
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
