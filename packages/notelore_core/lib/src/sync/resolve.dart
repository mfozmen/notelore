/// The model as the last resort for a true same-line sync conflict.
///
/// Only conflicts that [autoResolve] cannot settle get here. The model sees the
/// last synced lines and both edited versions and answers with the merged lines
/// plus one sentence on what it did; the sentence is kept for the sync report. Any
/// answer that cannot be read, and any provider failure, leaves the conflict open:
/// the engine then skips the file and tries again on the next sync.
library;

import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../text.dart';
import 'merge.dart';

const system =
    'You merge two edited versions of the same lines of a Markdown note that '
    'were changed on two devices. Keep every fact from both versions unless one clearly '
    'replaces the other; when entries carry dates, the later date wins. Never invent '
    "facts, dates or wording that is in neither version. Keep the note's line format.\n"
    '\n'
    'Answer with exactly two parts and nothing else:\n'
    '<merged>\n'
    'the merged lines\n'
    '</merged>\n'
    "<why>One sentence in the note's language on what you kept and why.</why>";

/// One model turn without tools: the system prompt and a user message in, the
/// answer's text out. The providers (#65) plug in here.
typedef Ask = Future<String> Function(String system, String prompt);

final _merged = RegExp(r'<merged>\n?(.*?)</merged>', dotAll: true);
final _why = RegExp(r'<why>(.*?)</why>', dotAll: true);

String _block(String title, List<String> lines) => '$title:\n```\n${lines.join()}```';

class ModelResolver {
  ModelResolver(this.ask);

  final Ask ask;
  final explanations = <String>[];

  Future<List<String>?> call(Conflict conflict) async {
    final prompt = [
      _block('Last synced version', conflict.base),
      _block('Edited on this device', conflict.local),
      _block('Edited on the other device', conflict.remote),
    ].join('\n\n');
    final String text;
    try {
      text = await ask(system, prompt);
    } on Exception {
      return null; // any provider failure (offline, quota, auth): the conflict stays open
    }
    final merged = _merged.firstMatch(text);
    final why = _why.firstMatch(text);
    if (merged == null || why == null) return null;
    final body = unorm.nfc(merged[1]!); // model output may come back NFD
    final lines = [for (final line in splitLines(body)) '$line\n'];
    var explanation = why[1]!.trim();
    if (lines.isEmpty) {
      // dropping facts must be visible to the user, not just reversible
      explanation = 'Removed the conflicting lines: $explanation';
    }
    explanations.add(explanation);
    return lines;
  }
}
