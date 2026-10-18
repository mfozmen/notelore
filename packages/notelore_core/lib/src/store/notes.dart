/// File operations on the notes folder.
///
/// Every write is atomic (temp file in the same directory, flush to disk, rename)
/// and only ever appends entries, marks a decision superseded, or moves content to
/// `_archive/`. Nothing here rewrites a file from model output or deletes anything.
/// Entry numbers are 1-based, as a user sees them. Ported from the Python reference.
///
/// The I/O is synchronous: note files are small. Callers on a UI thread run it in
/// an isolate.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../i18n.dart';
import '../text.dart';
import 'format.dart';

const kinds = {'project': 'projects', 'topic': 'topics'};
const archiveFolder = '_archive';

const _turkish = {
  'ç': 'c', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u', //
  'Ç': 'C', 'Ğ': 'G', 'İ': 'I', 'Ö': 'O', 'Ş': 'S', 'Ü': 'U',
};
final _reserved = {
  'con',
  'prn',
  'aux',
  'nul',
  for (var i = 1; i < 10; i++) ...['com$i', 'lpt$i'],
};
const _replaceAttempts = 5;
const _forbidden = '<>:"/\\|?*\n\r\x00';

/// Today's local calendar date, as the UTC midnight [DateTime] notes use for dates.
DateTime localToday() {
  final now = DateTime.now();
  return DateTime.utc(now.year, now.month, now.day);
}

// ---------------------------------------------------------------- paths

/// Lowercase ASCII file stem: Turkish letters transliterated, accents stripped.
String slugify(String title) {
  final text = unorm
      .nfkd(
        unorm
            .nfc(title)
            .replaceAllMapped(RegExp('[çğıöşüÇĞİÖŞÜ]'), (m) => _turkish[m[0]]!)
            .replaceAll(RegExp("['’]"), ''),
      )
      .replaceAll(RegExp(r'[^\x00-\x7F]'), '')
      .toLowerCase();
  var slug = text.replaceAll(RegExp('[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  slug = slug.substring(0, min(100, slug.length)).replaceFirst(RegExp(r'-+$'), '');
  if (slug.isEmpty) return 'untitled';
  return _reserved.contains(slug) ? '$slug-note' : slug;
}

/// Where originals are kept, under the notes root (#279).
const attachmentsFolder = 'attachments';

/// Keeps an attached file's original beside the notes, in a folder of [today]'s
/// date, under a safe name and never over another file ("-2" and on). Returns
/// its path relative to the root, for a note to link.
String keepAttachment(String root, String name, List<int> bytes, {DateTime? today}) {
  final base = p.basename(name.replaceAll(r'\', '/'));
  final extension = p.extension(base).toLowerCase().replaceAll(RegExp('[^.a-z0-9]'), '');
  final stem = slugify(p.basenameWithoutExtension(base));
  final folder = isoDate(today ?? localToday());
  for (var n = 1; ; n++) {
    final file = n == 1 ? '$stem$extension' : '$stem-$n$extension';
    final rel = '$attachmentsFolder/$folder/$file';
    final path = p.joinAll([root, ...rel.split('/')]);
    if (File(path).existsSync()) continue;
    atomicWriteBytes(path, bytes);
    return rel;
  }
}

String notePath(String root, String kind, String slug) {
  final folder = kinds[kind];
  if (folder == null) {
    throw ArgumentError.value(kind, 'kind', 'unknown note kind; expected one of ${kinds.keys}');
  }
  // A slug is a bare file stem: hand-made names like "My Note" are fine, path escapes are not.
  if (slug.isEmpty || slug == '.' || slug == '..' || slug.split('').any(_forbidden.contains)) {
    throw ArgumentError.value(slug, 'slug', 'invalid slug; use it exactly as list_notes shows it');
  }
  return p.join(root, folder, '$slug.md');
}

// ---------------------------------------------------------------- I/O

typedef Rename = void Function(String source, String target);
typedef Pause = void Function(Duration duration);

void _rename(String source, String target) => File(source).renameSync(target);

/// UTF-8, LF, written to a temp file next to [path] and renamed into place.
void atomicWrite(String path, String text, {Rename rename = _rename, Pause pause = sleep}) =>
    atomicWriteBytes(path, utf8.encode(text), rename: rename, pause: pause);

/// [atomicWrite] for bytes: an attachment (#279).
void atomicWriteBytes(
  String path,
  List<int> bytes, {
  Rename rename = _rename,
  Pause pause = sleep,
}) {
  Directory(p.dirname(path)).createSync(recursive: true);
  final random = Random();
  final suffix = List.generate(16, (_) => random.nextInt(256).toRadixString(16)).join();
  final tmp = File(p.join(p.dirname(path), '.${p.basename(path)}.$suffix.tmp'))
    ..createSync(exclusive: true); // created like any new file: other tools may open notes
  try {
    final handle = tmp.openSync(mode: FileMode.writeOnly);
    try {
      handle
        ..writeFromSync(bytes)
        ..flushSync();
    } finally {
      handle.closeSync();
    }
    moveWithRetry(tmp.path, path, rename: rename, pause: pause);
  } catch (_) {
    if (tmp.existsSync()) tmp.deleteSync();
    rethrow;
  }
}

/// Windows reports a file antivirus or an editor holds as access denied (5),
/// sharing (32) or lock (33) violation; POSIX as EPERM (1) or EACCES (13).
bool _held(FileSystemException error) =>
    const {1, 5, 13, 32, 33}.contains(error.osError?.errorCode);

/// Renames [source] to [target], retried briefly while the file is held.
void moveWithRetry(String source, String target, {Rename rename = _rename, Pause pause = sleep}) {
  for (var attempt = 0; attempt < _replaceAttempts - 1; attempt++) {
    try {
      rename(source, target);
      return;
    } on FileSystemException catch (error) {
      if (!_held(error)) rethrow;
      pause(Duration(milliseconds: 50 * (1 << attempt)));
    }
  }
  rename(source, target); // the last attempt lets the error out
}

/// The `*.md` files directly in [folder], sorted; none when it is missing.
List<File> markdownFiles(String folder) {
  final dir = Directory(folder);
  if (!dir.existsSync()) return [];
  return dir.listSync().whereType<File>().where((f) => f.path.endsWith('.md')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

Note readNote(String path) => parse(File(path).readAsStringSync());

/// Persists [note]; `updated` is maintained here, never by the caller.
void writeNote(String path, Note note, {DateTime? today}) {
  note.meta['updated'] = today ?? localToday();
  atomicWrite(path, unorm.nfc(serialize(note)));
}

// ---------------------------------------------------------------- sections and entries

String _lang(Note note) {
  final turkish = {for (final variants in sectionHeadings.values) variants['tr']};
  return note.sections.any((s) => turkish.contains(s.heading)) ? 'tr' : 'en';
}

bool _isBlank(NoteEntry entry) => entry is Raw && entry.text.trim().isEmpty;

/// The known section [key], created at the end of the file if missing.
Section _section(Note note, String key, [String? lang]) =>
    note.section(key) ?? _addSection(note, sectionHeading(key, lang ?? _lang(note)));

/// A new section called [heading] at the end of the file.
Section _addSection(Note note, String heading) {
  if (note.sections.isNotEmpty) {
    final previous = note.sections.last.entries;
    if (previous.isEmpty || !_isBlank(previous.last)) {
      previous.add(const Raw('')); // one blank line between sections
    }
  }
  final section = Section(heading);
  note.sections.add(section);
  return section;
}

/// Inserts after the last real entry, before the blank line that ends the section.
void _append(Section section, NoteEntry entry) {
  var index = section.entries.length;
  while (index > 0 && _isBlank(section.entries[index - 1])) {
    index--;
  }
  section.entries.insert(index, entry);
}

/// One clean entry text: NFC, continuation lines indented by two spaces.
String _text(String text) =>
    splitLines(unorm.nfc(text).trim()).map((line) => line.trim()).join('\n  ');

/// Index into the section's entries of the [number]-th real (non-Raw) entry.
int _position(Section section, int number) {
  final positions = [
    for (var i = 0; i < section.entries.length; i++)
      if (section.entries[i] is! Raw) i,
  ];
  if (number < 1 || number > positions.length) {
    throw RangeError('${section.heading} has ${positions.length} entries, no #$number');
  }
  return positions[number - 1];
}

// ---------------------------------------------------------------- operations

String createNote(
  String root,
  String kind,
  String title, {
  List<String>? tags,
  String lang = 'en',
  DateTime? today,
}) {
  final path = notePath(root, kind, slugify(title));
  if (File(path).existsSync()) throw FileSystemException('note already exists', path);
  final day = today ?? localToday();
  final meta = <String, Object?>{
    'title': title,
    'kind': kind,
    'created': day,
    'updated': day,
    if (tags != null && tags.isNotEmpty) 'tags': tags,
  };
  // Reminders get their section with the first one (#430), so most notes never show it.
  final sections = [
    for (final key in const ['decisions', 'notes', 'todo']) Section(sectionHeading(key, lang)),
  ];
  for (final section in sections.take(sections.length - 1)) {
    section.entries.add(const Raw(''));
  }
  writeNote(
    path,
    Note(meta, title, preamble: [''], sections: sections),
    today: day,
  );
  return path;
}

void addEntry(String path, String text, {DateTime? today}) {
  final note = readNote(path);
  final day = today ?? localToday();
  _append(_section(note, 'notes'), Entry(day, _text(text)));
  writeNote(path, note, today: day);
}

void addTodo(String path, String text, {DateTime? due, DateTime? today}) {
  final note = readNote(path);
  final day = today ?? localToday();
  _append(_section(note, 'todo'), Todo(due ?? day, _text(text)));
  writeNote(path, note, today: day);
}

/// Adds a reminder for [date], at [time] (`HH:MM`, local) if given (#430).
void addReminder(String path, String text, DateTime date, {String? time, DateTime? today}) {
  if (time != null && !RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(time)) {
    throw ArgumentError.value(time, 'time', 'a reminder time is HH:MM, 00:00 to 23:59');
  }
  final note = readNote(path);
  final day = today ?? localToday();
  _append(_section(note, 'reminders'), Reminder(date, _text(text), time: time));
  writeNote(path, note, today: day);
}

void completeTodo(String path, int number, {DateTime? today}) {
  final note = readNote(path);
  final section = _section(note, 'todo');
  final todos = [
    for (var i = 0; i < section.entries.length; i++)
      if (section.entries[i] case final Todo todo) (i, todo),
  ];
  if (number < 1 || number > todos.length) {
    throw RangeError('${section.heading} has ${todos.length} todos, no #$number');
  }
  final (position, todo) = todos[number - 1];
  section.entries[position] = Todo(todo.date, todo.text, done: true);
  writeNote(path, note, today: today);
}

/// Appends a decision; the active one for the same topic is superseded in the same write.
void recordDecision(String path, String topic, String value, {String? reason, DateTime? today}) {
  final key = _text(topic).toLowerCase();
  if (key.isEmpty || key.contains('*') || key.contains('\n')) {
    throw ArgumentError.value(topic, 'topic', 'decision topic must be a short one-line key');
  }
  final note = readNote(path);
  final day = today ?? localToday();
  final section = _section(note, 'decisions');
  for (var i = 0; i < section.entries.length; i++) {
    if (section.entries[i] case Decision(topic: final t, superseded: null) && final decision
        when t == key) {
      section.entries[i] = Decision(decision.date, t, decision.text, superseded: day);
    }
  }
  final why = reason == null || reason.isEmpty ? '' : ' ${_text(reason)}';
  _append(section, Decision(day, key, '${_text(value).replaceFirst(RegExp(r'\.+$'), '')}.$why'));
  writeNote(path, note, today: day);
}

/// The newest non-superseded decision for [topic]; deterministic, no model involved.
Decision? activeDecision(Note note, String topic) {
  final key = _text(topic).toLowerCase();
  return note
      .section('decisions')
      ?.entries
      .whereType<Decision>()
      .where((d) => d.topic == key && d.superseded == null)
      .lastOrNull;
}

/// Where archived entries of a note go: `_archive/<date>/entries/<path>`.
const _entries = 'entries';

/// Moves a whole file under `_archive/<date>/`, keeping its relative path and
/// never overwriting an earlier archive: the same note archived again that day
/// goes under `_archive/<date>-2/`, and so on.
String archiveNote(String root, String path, {DateTime? today}) {
  final day = isoDate(today ?? localToday());
  final relative = p.relative(path, from: root);
  var target = p.join(root, archiveFolder, day, relative);
  for (var number = 2; File(target).existsSync(); number++) {
    target = p.join(root, archiveFolder, '$day-$number', relative);
  }
  Directory(p.dirname(target)).createSync(recursive: true);
  moveWithRetry(path, target);
  return target;
}

/// A note (or part of one) in the archive.
final class ArchivedNote {
  const ArchivedNote(this.path, this.original, this.archivedOn, this.title, {this.entries = false});

  /// Where it lies now, under `_archive/<date>/`.
  final String path;

  /// Where it came from, relative to the notes root (`topics/x.md`).
  final String original;

  /// The day it was archived (`YYYY-MM-DD`).
  final String archivedOn;
  final String title;

  /// Only some entries of the note, not the whole note.
  final bool entries;
}

/// Everything in the archive, newest first.
List<ArchivedNote> listArchived(String root) => [
  if (Directory(p.join(root, archiveFolder)) case final archive when archive.existsSync())
    for (final file in archive.listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.md')) _archived(archive.path, file),
]..sort((a, b) => b.archivedOn.compareTo(a.archivedOn));

/// What [file] under the [archive] folder is: a whole note archived on
/// `<date>/<original path>`, or entries of one under `<date>/entries/`.
ArchivedNote _archived(String archive, File file) {
  final [day, ...rest] = p.split(p.relative(file.path, from: archive));
  final entries = rest.first == _entries && rest.length > 1;
  return ArchivedNote(
    file.path,
    (entries ? rest.skip(1) : rest).join('/'),
    day.substring(0, day.length.clamp(0, 10)), // `<date>-2` is that day too
    _titleOf(file),
    entries: entries,
  );
}

String _titleOf(File file) {
  try {
    return readNote(file.path).title;
  } on Exception {
    return p.basenameWithoutExtension(file.path); // not a note: named after the file
  }
}

/// A note with [original]'s name exists again: restoring would overwrite it.
class RestoreTaken implements Exception {
  const RestoreTaken(this.original);

  final String original;

  @override
  String toString() => 'a note at $original exists; not restored';
}

/// Moves [archived] back to where it came from; returns that path. Archived
/// entries go back into their note, or become it when it is gone. Never
/// overwrites: a whole note throws [RestoreTaken] when the place is taken.
String restoreArchived(String root, ArchivedNote archived, {DateTime? today}) {
  final target = p.joinAll([root, ...archived.original.split('/')]);
  if (archived.entries && File(target).existsSync()) {
    final note = readNote(target);
    for (final section in readNote(archived.path).sections) {
      if (section.key case final key?) {
        for (final entry in section.entries.where((e) => e is! Raw)) {
          _append(_section(note, key, _lang(note)), entry);
        }
      }
    }
    writeNote(target, note, today: today); // the note first: a failure here loses nothing
    File(archived.path).deleteSync(); // now in the note
    return target;
  }
  if (File(target).existsSync()) throw RestoreTaken(archived.original);
  Directory(p.dirname(target)).createSync(recursive: true);
  moveWithRetry(archived.path, target);
  return target;
}

/// Moves numbered entries per section into the archive copy of the same note.
String archiveEntries(
  String root,
  String path,
  Map<String, List<int>> selection, {
  DateTime? today,
}) {
  final note = readNote(path);
  final day = today ?? localToday();
  final target = p.join(root, archiveFolder, isoDate(day), _entries, p.relative(path, from: root));
  final archive = File(target).existsSync()
      ? readNote(target)
      : Note({...note.meta}, note.heading, preamble: ['']);
  for (final MapEntry(:key, value: numbers) in selection.entries) {
    final section = note.section(key);
    if (section == null || section.key == null) {
      throw ArgumentError.value(key, 'section', 'no known section in ${p.basename(path)}');
    }
    if (numbers.toSet().length != numbers.length) {
      throw ArgumentError.value(numbers, key, 'an entry is listed twice');
    }
    final positions = [for (final number in numbers) _position(section, number)];
    for (final position in positions) {
      _append(_section(archive, section.key!, _lang(note)), section.entries[position]);
    }
    for (final position in positions.toList()..sort((a, b) => b - a)) {
      section.entries.removeAt(position); // from the end: indexes stay valid
    }
  }
  writeNote(target, archive, today: day); // archive first: a failure here loses nothing
  writeNote(path, note, today: day);
  return target;
}

/// What [mergeNotes] did: where the source went, and how many of its entries
/// were added or already there.
typedef MergeResult = ({String archivedTo, int added, int duplicates});

/// Merges the note at [fromPath] into the one at [intoPath] (#229): every
/// entry, loose line, preamble line and unknown section of the source is
/// appended unless the target already has it; tags are joined; per decision
/// topic only the newest stays active. Then the source moves to the archive,
/// never deleted. The target is written first, so a failure loses nothing.
MergeResult mergeNotes(
  String root,
  String fromPath,
  String intoPath, {
  DateTime? today,
  Rename rename = _rename,
}) {
  if (p.equals(fromPath, intoPath)) {
    throw ArgumentError.value(fromPath, 'from', 'a note cannot be merged into itself');
  }
  final from = readNote(fromPath);
  final into = readNote(intoPath);
  final day = today ?? localToday();
  final tally = _Tally();
  _mergePreamble(into, from, tally);
  for (final section in from.sections) {
    _mergeSection(into, section, tally);
  }
  if (into.section('decisions') case final decisions?) _oneActivePerTopic(decisions);
  _joinTags(into, from);
  into.meta['updated'] = day;
  atomicWrite(intoPath, unorm.nfc(serialize(into)), rename: rename);
  return (
    archivedTo: archiveNote(root, fromPath, today: day),
    added: tally.added,
    duplicates: tally.duplicates,
  );
}

/// What a merge added, and what the target had already.
final class _Tally {
  var added = 0;
  var duplicates = 0;

  /// Adds [entry] to [target] unless it is blank or already there. A todo there
  /// in the other state is the same todo: it is kept once, done if either is (#283).
  void take(List<NoteEntry> target, NoteEntry entry) {
    if (_isBlank(entry)) return;
    final twin = entry is Todo
        ? target.indexWhere((t) => t is Todo && t.date == entry.date && t.text == entry.text)
        : -1;
    if (twin >= 0) {
      if ((entry as Todo).done) target[twin] = entry;
      duplicates++;
    } else if (target.contains(entry)) {
      duplicates++;
    } else {
      added++;
      target.add(entry);
    }
  }
}

/// The source's text above its first section, after the target's own.
void _mergePreamble(Note into, Note from, _Tally tally) {
  final lines = <NoteEntry>[];
  for (final line in from.preamble) {
    if (!into.preamble.contains(line)) tally.take(lines, Raw(line));
  }
  if (lines.isEmpty) return;
  var end = into.preamble.length;
  while (end > 0 && into.preamble[end - 1].trim().isEmpty) {
    end--;
  }
  into.preamble.insertAll(end, [
    if (end == 0) '',
    for (final Raw(:text) in lines.cast<Raw>()) text,
  ]);
}

/// The entries of [section] the target lacks, under the same section there.
void _mergeSection(Note into, Section section, _Tally tally) {
  final target = section.key == null
      ? into.section(section.heading) ?? _addSection(into, section.heading)
      : _section(into, section.key!, _lang(into));
  final merged = <NoteEntry>[...target.entries];
  for (final entry in section.entries) {
    tally.take(merged, entry);
  }
  // A todo of the target's own, done in the source, is done now.
  for (var i = 0; i < target.entries.length; i++) {
    target.entries[i] = merged[i];
  }
  for (final entry in merged.skip(target.entries.length).toList()) {
    _append(target, entry);
  }
}

/// Both notes' tags, each once, the target's first.
void _joinTags(Note into, Note from) {
  final tags = [
    for (final tags in [into.meta['tags'], from.meta['tags']])
      if (tags is List) ...tags,
  ];
  if (tags.isNotEmpty) into.meta['tags'] = tags.toSet().toList();
}

/// Two notes may each have an active decision for a topic: the newest stays,
/// the others are superseded on its date.
void _oneActivePerTopic(Section section) {
  final newest = <String, Decision>{};
  for (final entry in section.entries) {
    if (entry case Decision(superseded: null) && final d
        when !(newest[d.topic]?.date.isAfter(d.date) ?? false)) {
      newest[d.topic] = d;
    }
  }
  for (var i = 0; i < section.entries.length; i++) {
    if (section.entries[i] case Decision(superseded: null) && final d
        when !identical(newest[d.topic], d)) {
      section.entries[i] = Decision(d.date, d.topic, d.text, superseded: newest[d.topic]!.date);
    }
  }
}
