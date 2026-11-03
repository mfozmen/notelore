/// What the person told about themselves (#646): one Markdown file at the notes
/// root, a bullet a fact. Outside every kind folder, so it is never listed as a
/// note, never a cleanup candidate and never archived; it syncs like any note.
/// Only current facts stay in it, so the prompt never holds two answers; the
/// version before a change goes to `.notelore/history/`, never to the model.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'notes.dart';

const _heading = '# About me';
final _bullet = RegExp(r'^[-*] +(.*)$');

String aboutMePath(String root) => p.join(root, 'about-me.md');

/// The facts, in the file's order; none when there is no file.
List<String> aboutMe(String root) => [
  for (final line in _lines(root))
    if (_bullet.firstMatch(line) case final m?) m[1]!.trim(),
];

void rememberAboutMe(String root, String fact, {DateTime? now}) {
  final text = _fact(fact);
  if (_find(root, text) != null) throw ArgumentError('already known: $text');
  final lines = _lines(root);
  _write(
    root,
    [
      ...lines.every((line) => line.trim().isEmpty) ? [_heading, ''] : lines,
      '- $text',
    ],
    now,
    keep: false,
  );
}

void updateAboutMe(String root, String old, String fact, {DateTime? now}) {
  final text = _fact(fact);
  final at = _needed(root, old);
  final same = _find(root, text);
  if (same != null && same != at) throw ArgumentError('already known: $text');
  _write(root, [..._lines(root)]..[at] = '- $text', now);
}

void forgetAboutMe(String root, String fact, {DateTime? now}) {
  _write(root, [..._lines(root)]..removeAt(_needed(root, fact)), now);
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
    for (var n = 2; File(p.join(folder, 'about-me.md')).existsSync(); n++) {
      folder = p.join(root, '.notelore', 'history', '$stamp-$n');
    }
    atomicWrite(p.join(folder, 'about-me.md'), File(path).readAsStringSync());
  }
  atomicWrite(path, '${lines.join('\n')}\n');
}
