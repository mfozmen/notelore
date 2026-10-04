/// Deterministic cleanup candidates. The model only explains and ranks them.
///
/// Signals (`docs/note-format.md`): decisions superseded more than `decisionDays`
/// ago, files not updated for `fileDays`, open todos whose date is in the past.
/// Entry numbers are 1-based and match [archiveEntries]. Ported from the Python
/// reference.
library;

import 'package:path/path.dart' as p;

import 'format.dart';
import 'notes.dart';

final class Stale {
  const Stale(this.slug, this.kind, this.reason, this.section, this.number, this.date);

  final String slug;
  final String kind;

  /// "superseded decision" | "overdue todo" | "not updated"
  final String reason;

  /// Section key for an entry candidate, null for a whole file.
  final String? section;

  /// 1-based entry number, null for a whole file.
  final int? number;

  /// The date that made it stale.
  final DateTime date;

  @override
  bool operator ==(Object other) =>
      other is Stale &&
      other.slug == slug &&
      other.kind == kind &&
      other.reason == reason &&
      other.section == section &&
      other.number == number &&
      other.date == date;

  @override
  int get hashCode => Object.hash(slug, kind, reason, section, number, date);

  @override
  String toString() => 'Stale($kind/$slug, $reason, $section #$number, ${isoDate(date)})';
}

List<Stale> findStaleNotes(
  String root, {
  DateTime? today,
  int decisionDays = 90,
  int fileDays = 180,
}) {
  final day = today ?? localToday();
  final found = <Stale>[];
  for (final MapEntry(key: kind, value: folder) in kinds.entries) {
    for (final file in markdownFiles(p.join(root, folder))) {
      final Note note;
      try {
        note = readNote(file.path);
      } on NotANote {
        continue;
      }
      final slug = p.basenameWithoutExtension(file.path);
      found.addAll(_staleEntries(note, slug, kind, day, decisionDays));
      if (note.meta['updated'] case final DateTime updated) {
        final date = DateTime.utc(updated.year, updated.month, updated.day);
        if (day.difference(date).inDays > fileDays) {
          found.add(Stale(slug, kind, 'not updated', null, null, date));
        }
      }
    }
  }
  return found;
}

List<Stale> _staleEntries(Note note, String slug, String kind, DateTime today, int decisionDays) {
  final found = <Stale>[];
  for (final (key, reason) in [('decisions', 'superseded decision'), ('todo', 'overdue todo')]) {
    var number = 0;
    for (final entry in note.section(key)?.entries ?? const <NoteEntry>[]) {
      if (entry is Raw) continue;
      number++;
      final date = switch (entry) {
        Decision(:final superseded?) when today.difference(superseded).inDays > decisionDays =>
          superseded,
        Todo(done: false, :final date) when date.isBefore(today) => date,
        _ => null,
      };
      if (date != null) found.add(Stale(slug, kind, reason, key, number, date));
    }
  }
  return found;
}
