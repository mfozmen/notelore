/// The tool-use loop: the model decides *what* to do, the tools decide *how*.
/// Ported from the Python reference.
library;

import 'providers/base.dart';
import 'store/format.dart';
import 'store/notes.dart';
import 'tools.dart';

const _prompt = '''
You are Notelore, a note-taking assistant. The user talks; you keep tidy notes in Markdown files through the tools, and later answer questions from those notes.

Rules:
- Answer in the language the user writes in, and write note content in that language. Pass lang="tr" to create_note when the user writes Turkish.
- Every fact comes from a tool result. Never invent a note, a decision, a date or a todo.
- Notes are projects or topics. Call list_notes before creating one; when it is unclear which project or topic the user means, ask instead of guessing.
- "What did we decide about X?" is answered with get_decision, never from free text. Use decision_history only when the user asks how a decision changed.
- Note entries are one clean, self-contained sentence each; no "as discussed above".
- Decisions have a short lowercase topic key (database, hosting, auth). Record the reason when the user gave one.
- archive only after the user confirmed in this conversation which entries to archive.
- Keep replies short. Say what you saved or found; do not narrate tool calls.

Today is {today}.''';

const defaultMaxTurns = 20;
const _kept = {'text', 'tool_use'}; // the only block types the API accepts back as history

String systemPrompt([DateTime? today]) =>
    _prompt.replaceFirst('{today}', isoDate(today ?? localToday()));

class Agent {
  Agent(this.provider, this.toolbox, {this.today, this.maxTurns = defaultMaxTurns});

  final LlmProvider provider;
  final Toolbox toolbox;
  final DateTime? today;
  final int maxTurns;
  final messages = <Message>[];

  /// One user message in, the final text answer out; tool calls run in between.
  ///
  /// When the provider fails (offline, quota, auth) the whole turn is taken back
  /// out of [messages], so the history still alternates and the user can retry.
  /// Notes the tools already wrote stay written: the files are the truth.
  Future<String> ask(String text) async {
    final start = messages.length;
    try {
      return await _ask(text);
    } catch (_) {
      messages.removeRange(start, messages.length);
      rethrow;
    }
  }

  Future<String> _ask(String text) async {
    messages.add({'role': 'user', 'content': text});
    for (var turn = 0; turn < maxTurns; turn++) {
      final response = await provider.turn(systemPrompt(today), messages, toolbox.tools);
      // A tool_use outside a tool_use stop is half-built (e.g. cut by max_tokens):
      // never run it, and never keep it, since history needs a result for every call.
      final kept = response.stopReason == 'tool_use' ? _kept : const {'text'};
      final blocks = response.content.where((b) => kept.contains(b['type'])).toList();
      if (blocks.isEmpty) return _close('');
      messages.add({'role': 'assistant', 'content': blocks});
      final uses = blocks.where((b) => b['type'] == 'tool_use').toList();
      if (uses.isEmpty) {
        return blocks.map((b) => b['text']).join('\n');
      }
      messages.add({
        'role': 'user',
        'content': [for (final use in uses) _run(use)],
      });
    }
    return _close('I stopped after too many tool calls in a row. Please rephrase the request.');
  }

  /// Ends the turn with an assistant message so user and assistant keep alternating.
  String _close(String answer) {
    messages.add({
      'role': 'assistant',
      'content': [
        {'type': 'text', 'text': answer.isEmpty ? '[no answer]' : answer},
      ],
    });
    return answer;
  }

  Block _run(Block use) {
    final args = use['input'] ?? const <String, Object?>{};
    final result = switch (args) {
      {'__raw': final raw} => 'Error: the tool arguments were not valid JSON: $raw',
      final Map<String, Object?> map => toolbox.call('${use['name']}', map),
      _ => 'Error: the tool arguments must be a JSON object.',
    };
    return {'type': 'tool_result', 'tool_use_id': use['id'], 'content': result};
  }
}
