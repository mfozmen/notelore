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
void atomicWrite(String path, String text, {Rename rename = _rename, Pause pause = sleep}) {
  Directory(p.dirname(path)).createSync(recursive: true);
  final random = Random();
  final suffix = List.generate(16, (_) => random.nextInt(256).toRadixString(16)).join();
  final tmp = File(p.join(p.dirname(path), '.${p.basename(path)}.$suffix.tmp'))
    ..createSync(exclusive: true); // created like any new file: other tools may open notes
  try {
    final handle = tmp.openSync(mode: FileMode.writeOnly);
    try {
      handle
        ..writeStringSync(text)
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
Section _section(Note note, String key, [String? lang]) {
  final existing = note.section(key);
  if (existing != null) return existing;
  if (note.sections.isNotEmpty) {
    final previous = note.sections.last.entries;
    if (previous.isEmpty || !_isBlank(previous.last)) {
      previous.add(const Raw('')); // one blank line between sections
    }
  }
  final section = Section(sectionHeading(key, lang ?? _lang(note)));
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
  final sections = [for (final key in sectionHeadings.keys) Section(sectionHeading(key, lang))];
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

String _archivePath(String root, String path, DateTime today) =>
    p.join(root, archiveFolder, isoDate(today), p.relative(path, from: root));

/// Moves a whole file under `_archive/<date>/`, never overwriting an earlier archive.
String archiveNote(String root, String path, {DateTime? today}) {
  final first = _archivePath(root, path, today ?? localToday());
  Directory(p.dirname(first)).createSync(recursive: true);
  var target = first;
  for (var number = 2; File(target).existsSync(); number++) {
    target = p.join(p.dirname(first), '${p.basenameWithoutExtension(first)}-$number.md');
  }
  moveWithRetry(path, target);
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
  final target = _archivePath(root, path, day);
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
