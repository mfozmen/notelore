/// A turn the person marked wrong (#753): one Markdown file under
/// `.notelore/feedback/`, synced through their own Drive like the notes, so it
/// reaches the desktop where the model's training reads it. Never a note: no
/// kind folder lists it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'notes.dart';

const feedbackFolder = '.notelore/feedback';

/// Writes the last turn of [messages] (from the last message the person typed)
/// with [model] and what they [expected]; the file's path relative to [root].
String saveFeedback(
  String root,
  List<Map<String, Object?>> messages, {
  required String model,
  String expected = '',
  required DateTime now,
}) {
  final start = messages.lastIndexWhere(_typed);
  if (start < 0) throw ArgumentError('no message from the person');
  final stem = utcStamp(now);
  var rel = '$feedbackFolder/$stem.md';
  for (var n = 2; File(p.join(root, rel)).existsSync(); n++) {
    rel = '$feedbackFolder/$stem-$n.md';
  }
  final path = p.joinAll([root, ...rel.split('/')]);
  Directory(p.dirname(path)).createSync(recursive: true);
  final said = expected.trim().isEmpty ? '—' : expected.trim();
  final turn = const JsonEncoder.withIndent('  ').convert(_withoutImages(messages.sublist(start)));
  atomicWrite(
    path,
    '# Feedback, $stem\n\n- Model: $model\n- Expected: $said\n\n```json\n$turn\n```\n',
  );
  return rel;
}

/// A message the person wrote, not the tool results sent back as theirs.
bool _typed(Map<String, Object?> message) =>
    message['role'] == 'user' &&
    switch (message['content']) {
      final List<Object?> blocks => !blocks.any((b) => b is Map && b['type'] == 'tool_result'),
      _ => true,
    };

/// [value] with each picture's data left out: the file stays small.
Object? _withoutImages(Object? value) => switch (value) {
  {'type': 'image'} => const {'type': 'image'},
  final Map<Object?, Object?> map => {for (final e in map.entries) e.key: _withoutImages(e.value)},
  final List<Object?> list => [for (final item in list) _withoutImages(item)],
  _ => value,
};
