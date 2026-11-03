/// What the person told about themselves (#646): one Markdown file at the notes
/// root, a bullet a fact. Outside every kind folder, so it is never listed as a
/// note, never a cleanup candidate and never archived; it syncs like any note.
/// Only current facts stay in it, so the prompt never holds two answers; the
/// version before a change goes to `.notelore/history/`, never to the model.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../i18n.dart';
import 'notes.dart';

const _heading = '# About me';
final _bullet = RegExp(r'^[-*] +(.*)$');
final _section = RegExp(r'^## +(.*?)\s*$');

/// A known section's key for a heading in either language, else null.
String? _keyOf(String heading) => [
  for (final MapEntry(:key, :value) in aboutMeSections.entries)
    if (value.values.contains(heading)) key,
].firstOrNull;

/// The file's name, relative to the notes root.
const aboutMeFile = 'about-me.md';

String aboutMePath(String root) => p.join(root, aboutMeFile);

/// The facts, in the file's order; none when there is no file.
List<String> aboutMe(String root) => [for (final f in aboutMeFacts(root)) f.fact];

/// Each fact with its section key ([aboutMeSections]), in the file's order. A
/// bullet before any heading, or under one Notelore does not know, is Other.
List<({String section, String fact})> aboutMeFacts(String root) {
  final facts = <({String section, String fact})>[];
  var section = 'other';
  for (final line in _lines(root)) {
    if (_section.firstMatch(line) case final m?) {
      section = _keyOf(m[1]!) ?? 'other';
    } else if (_bullet.firstMatch(line) case final m?) {
      facts.add((section: section, fact: m[1]!.trim()));
    }
  }
  return facts;
}

/// Adds [fact] at the end of [section]. A new heading speaks the file's
/// language when it has known headings, else [lang].
void rememberAboutMe(
  String root,
  String fact, {
  String section = 'other',
  String lang = 'en',
  DateTime? now,
}) {
  final text = _fact(fact);
  _known(section);
  if (_find(root, text) != null) throw ArgumentError('already known: $text');
  final lines = _lines(root);
  final start = lines.every((line) => line.trim().isEmpty) ? [_heading, ''] : lines;
  _write(root, _insert(start, text, section, lang), now, keep: false);
}

/// Replaces [old] with [fact]: in place, or at the end of [section] when given.
void updateAboutMe(
  String root,
  String old,
  String fact, {
  String? section,
  String lang = 'en',
  DateTime? now,
}) {
  final text = _fact(fact);
  final at = _needed(root, old);
  final same = _find(root, text);
  if (same != null && same != at) throw ArgumentError('already known: $text');
  final lines = [..._lines(root)];
  if (section == null || section == _sectionAt(lines, at)) {
    _write(root, lines..[at] = '- $text', now);
    return;
  }
  _known(section);
  _write(root, _insert(_pruned(lines..removeAt(at)), text, section, lang), now);
}

void forgetAboutMe(String root, String fact, {DateTime? now}) {
  _write(root, _pruned([..._lines(root)]..removeAt(_needed(root, fact))), now);
}

void _known(String section) {
  if (!aboutMeSections.containsKey(section)) {
    throw ArgumentError.value(section, 'section', 'one of ${aboutMeSections.keys.join(', ')}');
  }
}

String _sectionAt(List<String> lines, int at) {
  for (var i = at; i >= 0; i--) {
    if (_section.firstMatch(lines[i]) case final m?) return _keyOf(m[1]!) ?? 'other';
  }
  return 'other';
}

/// The first heading at or after [from], or the end.
int _nextHeading(List<String> lines, int from) {
  final at = lines.indexWhere(_section.hasMatch, from);
  return at < 0 ? lines.length : at;
}

/// Just past the last non-blank line in [from]..[to], or [from] when all are blank.
int _textEnd(List<String> lines, int from, int to) {
  var end = to;
  while (end > from && lines[end - 1].trim().isEmpty) {
    end--;
  }
  return end;
}

List<String> _insert(List<String> lines, String text, String section, String lang) {
  final bullet = '- $text';
  if (section == 'other') {
    // Above the first heading, wherever the file starts.
    final first = _nextHeading(lines, 0);
    final at = _textEnd(lines, 0, first);
    return lines..insertAll(at, [
      if (at > 0 && !_bullet.hasMatch(lines[at - 1])) '',
      bullet,
      if (at == first && first < lines.length) '',
    ]);
  }
  final own = lines.indexWhere((line) => _keyOfLine(line) == section);
  if (own >= 0) {
    final at = _textEnd(lines, own + 1, _nextHeading(lines, own + 1));
    return lines..insertAll(at, [if (at == own + 1) '', bullet]);
  }
  return _newSection(lines, bullet, section, lang);
}

/// A heading [section] in its place in the order, with [bullet] under it.
List<String> _newSection(List<String> lines, String bullet, String section, String lang) {
  final order = aboutMeSections.keys.toList();
  final next = lines.indexWhere((line) {
    final key = _keyOfLine(line);
    return key != null && order.indexOf(key) > order.indexOf(section);
  });
  final before = next < 0 ? lines.length : next;
  final at = _textEnd(lines, 0, before);
  final names = aboutMeSections[section]!;
  final heading = names[_spoken(lines) ?? lang] ?? names['en']!;
  return lines..insertAll(at, ['', '## $heading', '', bullet, if (at == before && next >= 0) '']);
}

/// The language of the file's known headings, if it has any.
String? _spoken(List<String> lines) {
  for (final line in lines) {
    final name = _section.firstMatch(line)?[1];
    if (name == null || _keyOf(name) == null) continue;
    return aboutMeSections[_keyOf(name)]!['tr'] == name ? 'tr' : 'en';
  }
  return null;
}

/// The known section [line] heads, else null.
String? _keyOfLine(String line) => switch (_section.firstMatch(line)) {
  final m? => _keyOf(m[1]!),
  null => null,
};

/// Without the known headings left with nothing under them.
List<String> _pruned(List<String> lines) {
  for (var i = lines.length - 1; i >= 0; i--) {
    if (i >= lines.length || _keyOfLine(lines[i]) == null) continue;
    final next = _nextHeading(lines, i + 1);
    if (_textEnd(lines, i + 1, next) > i + 1) continue;
    final from = i > 0 && lines[i - 1].trim().isEmpty ? i - 1 : i;
    lines.removeRange(from, next == lines.length ? next : next - 1);
  }
  return lines;
}

String _fact(String fact) {
  final text = unorm.nfc(fact.replaceAll(RegExp(r'\s+'), ' ').trim());
  if (text.isEmpty) throw ArgumentError('an empty fact');
  return text;
}

String _key(String text) => unorm.nfc(text).toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

List<String> _lines(String root) {
  final file = File(aboutMePath(root));
  if (!file.existsSync()) return [];
  final lines = unorm.nfc(file.readAsStringSync()).replaceAll('\r\n', '\n').split('\n');
  return lines.last.isEmpty ? lines.sublist(0, lines.length - 1) : lines;
}

int? _find(String root, String fact) {
  final lines = _lines(root);
  for (var i = 0; i < lines.length; i++) {
    final m = _bullet.firstMatch(lines[i]);
    if (m != null && _key(m[1]!) == _key(fact)) return i;
  }
  return null;
}

int _needed(String root, String fact) =>
    _find(root, fact) ?? (throw ArgumentError('not a known fact: $fact'));

void _write(String root, List<String> lines, DateTime? now, {bool keep = true}) {
  final path = aboutMePath(root);
  if (keep) {
    final t = (now ?? DateTime.now()).toUtc();
    String two(int n) => '$n'.padLeft(2, '0');
    final stamp =
        '${t.year}-${two(t.month)}-${two(t.day)}T${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
    // Two changes in one second must not share a folder: the second copy would
    // replace the first, and that version would be gone.
    var folder = p.join(root, '.notelore', 'history', stamp);
    for (var n = 2; File(p.join(folder, aboutMeFile)).existsSync(); n++) {
      folder = p.join(root, '.notelore', 'history', '$stamp-$n');
    }
    atomicWrite(p.join(folder, aboutMeFile), File(path).readAsStringSync());
  }
  final kept = [...lines];
  while (kept.isNotEmpty && kept.last.trim().isEmpty) {
    kept.removeLast();
  }
  atomicWrite(path, '${kept.join('\n')}\n');
}
