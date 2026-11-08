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
  String verdict = 'bad',
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
    '# Feedback, $stem\n\n- Model: $model\n- Expected: $said\n'
    '- Verdict: $verdict\n\n```json\n$turn\n```\n',
  );
  return rel;
}

/// The good and bad reports under [root]'s feedback folder, by the model that
/// answered; a file without a verdict counts as bad, like the old ones (#833).
Map<String, ({int good, int bad})> feedbackCounts(String root) {
  final dir = Directory(p.joinAll([root, ...feedbackFolder.split('/')]));
  if (!dir.existsSync()) return const {};
  final counts = <String, ({int good, int bad})>{};
  for (final file in dir.listSync().whereType<File>()) {
    if (!file.path.endsWith('.md')) continue;
    final text = file.readAsStringSync();
    final model = RegExp(r'^- Model: (.*)$', multiLine: true).firstMatch(text)?.group(1)?.trim();
    if (model == null || model.isEmpty) continue;
    final good = RegExp(r'^- Verdict: good$', multiLine: true).hasMatch(text);
    final old = counts[model] ?? (good: 0, bad: 0);
    counts[model] = good ? (good: old.good + 1, bad: old.bad) : (good: old.good, bad: old.bad + 1);
  }
  return counts;
}

const _reminderMark = '(Notelore)';

/// What the agent tells the model when it answers while a note it just made
/// is still empty; sent as a user message, but not the person's words.
String emptyNoteReminder(List<String> notes) =>
    '$_reminderMark ${notes.join(', ')} ${notes.length == 1 ? 'is' : 'are'} still empty: '
    'add what the user said, or say why it stays empty.';

/// A message the person wrote, not the tool results or reminders sent as theirs.
bool _typed(Map<String, Object?> message) =>
    message['role'] == 'user' &&
    switch (message['content']) {
      final List<Object?> blocks => !blocks.any(
        (b) =>
            b is Map &&
            (b['type'] == 'tool_result' ||
                (b['text'] is String && (b['text'] as String).startsWith(_reminderMark))),
      ),
      _ => true,
    };

/// [value] with each picture's data left out: the file stays small.
Object? _withoutImages(Object? value) => switch (value) {
  {'type': 'image'} => const {'type': 'image'},
  final Map<Object?, Object?> map => {for (final e in map.entries) e.key: _withoutImages(e.value)},
  final List<Object?> list => [for (final item in list) _withoutImages(item)],
  _ => value,
};
