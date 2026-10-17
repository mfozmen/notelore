/// Notes in and out of Notelore (#215): importing a note someone sent, and the
/// pieces an export needs.
///
/// A Markdown export is the note file itself, byte for byte, so it can come back
/// in through [importNote] unchanged. HTML and PDF are for reading: [notesHtml]
/// is a whole page, [outline] the plain lines a PDF lays out. Importing never
/// overwrites a note: a taken name gets a numbered title beside it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:markdown/markdown.dart' as md;
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'format.dart';
import 'notes.dart';

enum ImportOutcome {
  /// A new note, under its own name.
  added,

  /// A different note had the name: this one came in as "<title> (2)" and so on.
  renamed,

  /// Exactly this note is here already; nothing was written.
  alreadyThere,
}

final class Imported {
  const Imported(this.outcome, this.title, this.path);

  final ImportOutcome outcome;
  final String title;
  final String path;
}

/// Adds the note in [text] to the notes folder at [root]. The text must be a
/// Notelore note (front matter with a title and a known kind); anything else
/// throws [NotANote] and writes nothing. It is stored as LF and NFC.
Imported importNote(String root, String text) {
  final incoming = unorm.nfc(text.replaceAll('\r\n', '\n'));
  final note = parse(incoming);
  final kind = '${note.meta['kind']}';
  if (!kinds.containsKey(kind)) throw NotANote('unknown note kind: $kind');
  for (var n = 1; ; n++) {
    final title = n == 1 ? note.title : '${note.title} ($n)';
    final content = n == 1 ? incoming : serialize(_retitled(note, title));
    final path = notePath(root, kind, slugify(title));
    final file = File(path);
    if (!file.existsSync()) {
      file.parent.createSync(recursive: true);
      atomicWrite(path, content);
      return Imported(n == 1 ? ImportOutcome.added : ImportOutcome.renamed, title, path);
    }
    if (unorm.nfc(file.readAsStringSync().replaceAll('\r\n', '\n')) == content) {
      return Imported(ImportOutcome.alreadyThere, title, path);
    }
  }
}

Note _retitled(Note note, String title) =>
    Note({...note.meta, 'title': title}, title, preamble: note.preamble, sections: note.sections);

enum LineStyle { title, meta, heading, item, text }

/// One line of a note as a reader sees it: no Markdown marks left.
final class OutlineLine {
  const OutlineLine(this.style, this.text, {this.struck = false});

  final LineStyle style;

  /// May hold line breaks: an entry's continuation lines.
  final String text;

  /// A superseded decision, shown struck through.
  final bool struck;
}

/// The note in [text] as lines to lay out: title, a meta line (kind, tags,
/// created – updated), then each section and its entries. Blank lines go.
List<OutlineLine> outline(String text) {
  final note = parse(text);
  return [
    OutlineLine(LineStyle.title, note.title),
    OutlineLine(LineStyle.meta, metaLine(note)),
    for (final line in note.preamble)
      if (line.trim().isNotEmpty) OutlineLine(LineStyle.text, line.trim()),
    for (final section in note.sections) ...[
      OutlineLine(LineStyle.heading, section.heading),
      for (final entry in section.entries) ?_line(entry),
    ],
  ];
}

OutlineLine? _line(NoteEntry entry) => switch (entry) {
  Entry(:final date, :final text) => OutlineLine(
    LineStyle.item,
    '${isoDate(date)}: ${_flat(text)}',
  ),
  Decision(:final date, :final topic, :final text, :final superseded) => OutlineLine(
    LineStyle.item,
    '${isoDate(date)} — $topic: $text'
    '${superseded == null ? '' : ' (superseded ${isoDate(superseded)})'}',
    struck: superseded != null,
  ),
  Todo(:final date, :final text, :final done) => OutlineLine(
    LineStyle.item,
    '[${done ? 'x' : ' '}] ${isoDate(date)}: ${_flat(text)}',
  ),
  Raw(:final text) when text.trim().isEmpty => null,
  Raw(:final text) =>
    text.startsWith('- ')
        ? OutlineLine(LineStyle.item, _flat(text.substring(2)))
        : OutlineLine(LineStyle.text, _flat(text)),
};

/// Continuation lines without their two-space indent.
String _flat(String text) => text.replaceAll('\n  ', '\n');

/// "project · investing, side-project · 2026-09-12 – 2026-09-30": what the
/// front matter says, for a reader.
String metaLine(Note note) {
  String show(Object? value) => value is DateTime ? isoDate(value) : '$value';
  final tags = note.meta['tags'];
  final created = note.meta['created'];
  final updated = note.meta['updated'];
  return [
    show(note.meta['kind']),
    if (tags is List && tags.isNotEmpty) tags.map(show).join(', '),
    if (created != null || updated != null)
      [if (created != null) show(created), if (updated != null) show(updated)].join(' – '),
  ].join(' · ');
}

const _escape = HtmlEscape(HtmlEscapeMode.element);

/// The notes in [texts] as one HTML page called [title], each an `<article>`
/// with its meta line. Markup inside a note is shown as text, never run.
String notesHtml(String title, List<String> texts) {
  final articles = [
    for (final text in texts)
      () {
        final source = unorm.nfc(text.replaceAll('\r\n', '\n'));
        final note = parse(source);
        // The body after the "# title" line, its own markup escaped first.
        final body = source.substring(source.indexOf('\n# ') + 1).split('\n').skip(1).join('\n');
        final html = md.markdownToHtml(
          _escape.convert(body),
          extensionSet: md.ExtensionSet.gitHubFlavored,
        );
        return '<article>\n<h1>${_escape.convert(note.title)}</h1>\n'
            '<p class="meta">${_escape.convert(metaLine(note))}</p>\n$html</article>';
      }(),
  ];
  return '''<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_escape.convert(title)}</title>
<style>
body { font-family: system-ui, sans-serif; max-width: 46rem; margin: 2rem auto; padding: 0 1rem; line-height: 1.5; }
.meta { color: #666; }
article + article { border-top: 1px solid #ccc; margin-top: 2rem; padding-top: 1rem; }
</style>
</head>
<body>
${articles.join('\n')}
</body>
</html>
''';
}
