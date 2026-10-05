/// Parse and serialize the note format from `docs/note-format.md`.
///
/// Pure functions, no I/O. `serialize(parse(text))` returns `text` byte for byte for
/// every canonical file; CRLF input is normalized to LF and NFD to NFC on parse.
/// Nothing is dropped: lines that do not match an entry pattern survive as [Raw],
/// and blank lines are `Raw('')` entries of the section they sit in. Ported from the
/// Python reference; both must meet `spec/fixtures/notes`.
library;

import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../i18n.dart';
import 'front_matter.dart';

const _date = r'(\d{4}-\d{2}-\d{2})';
// Dart's RegExp has no conditional groups, so active and superseded decisions get one each.
final _decision = RegExp('^- $_date — \\*\\*([^*\\n]+)\\*\\*: (.*)\$', dotAll: true);
final _superseded = RegExp(
  '^- ~~$_date — \\*\\*([^*\\n]+)\\*\\*: (.*?)~~ _\\(superseded $_date\\)_\$',
  dotAll: true,
);
final _entry = RegExp('^- $_date: (.*)\$', dotAll: true);
final _todo = RegExp('^- \\[([ x])\\] $_date: (.*)\$', dotAll: true);

/// `YYYY-MM-DD` of a date.
String isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// The date in `YYYY-MM-DD` [text], or null for an impossible one such as 2026-13-45, which the
/// parser keeps verbatim instead of guessing (DateTime.parse would roll it over).
DateTime? parseIsoDate(String text) {
  final [year, month, day] = text.split('-').map(int.parse).toList();
  if (year < 1) return null; // Python's date has no year 0
  final date = DateTime.utc(year, month, day);
  return date.month == month && date.day == day ? date : null;
}

/// The text is not a note: no front matter, no title, or no `# <title>` line.
class NotANote extends FormatException {
  const NotANote(super.message);

  @override
  String toString() => 'NotANote: $message';
}

sealed class NoteEntry {
  const NoteEntry();

  String render();

  @override
  String toString() => '$runtimeType(${render()})';
}

final class Decision extends NoteEntry {
  const Decision(this.date, this.topic, this.text, {this.superseded});

  final DateTime date;
  final String topic;

  /// `<value>. <optional reason>`, verbatim.
  final String text;
  final DateTime? superseded;

  String get value {
    final cut = text.indexOf('. ');
    return (cut < 0 ? text : text.substring(0, cut)).replaceFirst(RegExp(r'\.+$'), '');
  }

  String? get reason {
    final cut = text.indexOf('. ');
    return cut < 0 ? null : text.substring(cut + 2);
  }

  @override
  String render() {
    final line = '- ${superseded != null ? '~~' : ''}${isoDate(date)} — **$topic**: $text';
    return superseded == null ? line : '$line~~ _(superseded ${isoDate(superseded!)})_';
  }

  @override
  bool operator ==(Object other) =>
      other is Decision &&
      other.date == date &&
      other.topic == topic &&
      other.text == text &&
      other.superseded == superseded;

  @override
  int get hashCode => Object.hash(date, topic, text, superseded);
}

final class Entry extends NoteEntry {
  const Entry(this.date, this.text);

  final DateTime date;

  /// Continuation lines keep their "\n  " indentation.
  final String text;

  @override
  String render() => '- ${isoDate(date)}: $text';

  @override
  bool operator ==(Object other) => other is Entry && other.date == date && other.text == text;

  @override
  int get hashCode => Object.hash(date, text);
}

final class Todo extends NoteEntry {
  const Todo(this.date, this.text, {this.done = false});

  final DateTime date;
  final String text;
  final bool done;

  @override
  String render() => '- [${done ? 'x' : ' '}] ${isoDate(date)}: $text';

  @override
  bool operator ==(Object other) =>
      other is Todo && other.date == date && other.text == text && other.done == done;

  @override
  int get hashCode => Object.hash(date, text, done);
}

/// A line (or bullet block) that is not a recognized entry. Preserved verbatim.
final class Raw extends NoteEntry {
  const Raw(this.text);

  final String text;

  @override
  String render() => text;

  @override
  bool operator ==(Object other) => other is Raw && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

class Section {
  Section(this.heading, [List<NoteEntry>? entries]) : entries = entries ?? [];

  /// Verbatim, e.g. "Kararlar".
  final String heading;
  final List<NoteEntry> entries;

  String? get key => sectionKey(heading);
}

class Note {
  Note(this.meta, this.heading, {List<String>? preamble, List<Section>? sections})
    : preamble = preamble ?? [],
      sections = sections ?? [];

  /// Front matter, insertion order preserved.
  final Map<String, Object?> meta;

  /// The "# ..." line, verbatim.
  final String heading;

  /// Lines between the title and the first section.
  final List<String> preamble;
  final List<Section> sections;

  String get title => '${meta['title']}';

  Section? section(String keyOrHeading) {
    for (final section in sections) {
      if (section.key == keyOrHeading || section.heading == keyOrHeading) return section;
    }
    return null;
  }
}

Note parse(String input) {
  final text = unorm.nfc(input.replaceAll('\r\n', '\n'));
  if (!text.startsWith('---\n')) throw const NotANote('missing YAML front matter');
  final end = text.indexOf('\n---\n', 4);
  if (end < 0) throw const NotANote('unterminated YAML front matter');
  final Map<String, Object?> meta;
  try {
    meta = loadFrontMatter(text.substring(4, end + 1));
  } on FormatException catch (error) {
    throw NotANote(error.message);
  }
  if (!meta.containsKey('title')) {
    throw const NotANote('front matter must be a mapping with a title');
  }
  var body = text.substring(end + 5);
  if (body.endsWith('\n')) body = body.substring(0, body.length - 1);
  final lines = body.isEmpty ? <String>[] : body.split('\n');
  if (lines.isEmpty || !lines.first.startsWith('# ')) {
    throw const NotANote("missing '# <title>' line after the front matter");
  }

  final note = Note(meta, lines.first.substring(2));
  var current = note.preamble;
  final blocks = <(Section, List<String>)>[];
  for (final line in lines.skip(1)) {
    if (line.startsWith('## ')) {
      final section = Section(line.substring(3));
      note.sections.add(section);
      current = [];
      blocks.add((section, current));
    } else {
      current.add(line);
    }
  }
  for (final (section, sectionLines) in blocks) {
    section.entries.addAll(_parseEntries(section.key, sectionLines));
  }
  return note;
}

List<NoteEntry> _parseEntries(String? key, List<String> lines) {
  if (key == null) return [for (final line in lines) Raw(line)];
  final entries = <NoteEntry>[];
  final block = <String>[];

  void flush() {
    if (block.isEmpty) return;
    entries.add(_parseBlock(key, block.join('\n')));
    block.clear();
  }

  for (final line in lines) {
    if (line.startsWith('- ')) {
      flush();
      block.add(line);
    } else if (block.isNotEmpty && (line.startsWith(' ') || line.startsWith('\t'))) {
      block.add(line);
    } else {
      flush();
      entries.add(Raw(line));
    }
  }
  flush();
  return entries;
}

NoteEntry _parseBlock(String key, String block) {
  switch (key) {
    case 'decisions':
      if (_superseded.firstMatch(block) case final m?) {
        final (date, superseded) = (parseIsoDate(m[1]!), parseIsoDate(m[4]!));
        if (date != null && superseded != null) {
          return Decision(date, m[2]!, m[3]!, superseded: superseded);
        }
      } else if (_decision.firstMatch(block) case final m?) {
        if (parseIsoDate(m[1]!) case final date?) return Decision(date, m[2]!, m[3]!);
      }
    case 'notes':
      if (_entry.firstMatch(block) case final m?) {
        if (parseIsoDate(m[1]!) case final date?) return Entry(date, m[2]!);
      }
    case 'todo':
      if (_todo.firstMatch(block) case final m?) {
        if (parseIsoDate(m[2]!) case final date?) return Todo(date, m[3]!, done: m[1] == 'x');
      }
  }
  return Raw(block);
}

String serialize(Note note) {
  final out = StringBuffer('---\n')
    ..write(dumpFrontMatter(note.meta))
    ..write('---\n')
    ..write('# ${note.heading}\n');
  for (final line in note.preamble) {
    out.write('$line\n');
  }
  for (final section in note.sections) {
    out.write('## ${section.heading}\n');
    for (final entry in section.entries) {
      out.write('${entry.render()}\n');
    }
  }
  return out.toString();
}
