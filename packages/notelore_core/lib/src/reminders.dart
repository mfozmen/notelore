/// The reminders the device should notify of (#431): read from the notes, the
/// one place they live. The app schedules exactly these and cancels any other
/// it scheduled before, so processing the notes again never doubles one.
library;

import 'dart:convert';

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
      final Note note;
      try {
        note = readNote(file.path);
      } on NotANote {
        continue;
      }
      final rel = p.posix.joinAll(p.split(p.relative(file.path, from: root)));
      for (final reminder in note.section('reminders')?.entries.whereType<Reminder>() ?? []) {
        final at = _at(reminder);
        if (at.isAfter(now)) {
          due.add(
            DueReminder(_id('$rel\n${reminder.render()}'), at, note.title, _flat(reminder.text)),
          );
        }
      }
    }
  }
  due.sort((a, b) => a.at.compareTo(b.at));
  return due.take(maxScheduledReminders).toList();
}

DateTime _at(Reminder reminder) {
  final [hour, minute] = (reminder.time ?? '$_morning:00').split(':').map(int.parse).toList();
  final day = reminder.date;
  return DateTime(day.year, day.month, day.day, hour, minute);
}

/// FNV-1a over the UTF-8 bytes, kept to 31 bits: a platform's positive int32.
int _id(String key) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(key)) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}

/// Continuation lines as one line of text.
String _flat(String text) => text.replaceAll('\n  ', ' ');
