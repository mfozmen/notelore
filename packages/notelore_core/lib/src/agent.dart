/// The tool-use loop: the model decides *what* to do, the tools decide *how*.
/// Ported from the Python reference.
library;

import 'dart:async';

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
- Keep every detail the user gave (who it is for, names, titles, places, dates) in the entry; never shorten "buy the book X for my brother" to "buy X".
- Messages may be dictated, and speech recognition spells English product and technical terms the way they sound in the user's language (Turkish "deyta beys" means "database", "pull rikuest" means "pull request"). Never save such a sound-alike spelling: write the English term in its usual spelling, in notes and answers, keeping the rest of the sentence in the user's language. Ask when you cannot tell which term was meant.
- When a phrase could be a title or a name and you cannot tell which (e.g. "abim Deniz": "my brother Deniz", or the book "Abim Deniz"?), ask before saving.
- If search_notes finds nothing, call list_notes and read_note the likely notes before saying you do not know.
- If you can search the web, do so only when it helps get a note right: a book, film, person, place or fact the user names that you are not sure about. Save what the source says (for example the author of a book) and keep the user's own words; never search for things the notes already answer.
- Decisions have a short lowercase topic key (database, hosting, auth). Record the reason when the user gave one.
- archive only after the user confirmed in this conversation which entries to archive.
- Keep replies short. Say what you saved or found; do not narrate tool calls.

Today is {today}.''';

const defaultMaxTurns = 20;

/// The turn was stopped: by the user, or because it ran past the deadline.
class TurnStopped implements Exception {
  const TurnStopped([this.message = 'Stopped.']);

  final String message;

  @override
  String toString() => message;
}

/// What a tool round is doing, for the user to see while they wait.
String describeTool(String name) => switch (name) {
  'search_notes' || 'list_notes' => 'Searching the notes',
  'read_note' || 'get_decision' || 'decision_history' => 'Reading the notes',
  _ when writingTools.contains(name) => 'Writing the notes',
  _ => 'Working',
};

/// The tools that change the notes folder.
const writingTools = {
  'create_note',
  'add_note_entry',
  'add_todo',
  'complete_todo',
  'record_decision',
  'archive',
};

const _kept = {'text', 'tool_use'}; // the only block types the API accepts back as history

String systemPrompt([DateTime? today]) =>
    _prompt.replaceFirst('{today}', isoDate(today ?? localToday()));

class Agent {
  Agent(
    this.provider,
    this.toolbox, {
    this.today,
    this.maxTurns = defaultMaxTurns,
    this.deadline = const Duration(minutes: 3),
  });

  final LlmProvider provider;
  final Toolbox toolbox;
  final DateTime? today;
  final int maxTurns;

  /// How long a whole turn, every model call and tool round, may take.
  final Duration deadline;
  final messages = <Message>[];

  /// Whether the last [ask] called a tool that writes the notes. A failed turn
  /// is taken back out of [messages] but its writes stay, so asking the same
  /// again may write them twice.
  var wroteNotes = false;

  /// Completes with [TurnStopped] to end the running turn.
  Completer<AgentResponse>? _stop;

  /// Ends the running turn at once, if there is one; [ask] throws [TurnStopped].
  void stop([TurnStopped reason = const TurnStopped()]) {
    if (_stop case final stop? when !stop.isCompleted) stop.completeError(reason);
  }

  /// One user message in, the final text answer out; tool calls run in between.
  ///
  /// When the provider fails (offline, quota, auth) the whole turn is taken back
  /// out of [messages], so the history still alternates and the user can retry.
  /// Notes the tools already wrote stay written: the files are the truth.
  /// The same holds when the turn is stopped ([stop], or past [deadline]).
  /// [onStep] hears what the turn is doing ("Thinking", [describeTool]).
  /// [takeLater] hands over what the user wrote while the turn ran; it joins
  /// the next step, so the one final answer covers it.
  Future<String> ask(
    String text, {
    void Function(String step)? onStep,
    List<String> Function()? takeLater,
  }) async {
    final start = messages.length;
    wroteNotes = false;
    final stop = _stop = Completer()..future.ignore();
    final timer = Timer(deadline, () => this.stop(const TurnStopped(_late)));
    try {
      return await _ask(text, onStep ?? (_) {}, takeLater ?? () => const [], stop.future);
    } catch (_) {
      messages.removeRange(start, messages.length);
      rethrow;
    } finally {
      timer.cancel();
    }
  }

  static const _late = 'No answer in time, so I stopped. Please try again.';

  Future<String> _ask(
    String text,
    void Function(String step) onStep,
    List<String> Function() takeLater,
    Future<AgentResponse> stopped,
  ) async {
    messages.add({'role': 'user', 'content': text});
    for (var turn = 0; turn < maxTurns; turn++) {
      onStep('Thinking');
      // A stopped turn does not wait for the model: its answer is dropped.
      final response = await Future.any([
        provider.turn(systemPrompt(today), messages, toolbox.tools),
        stopped,
      ]);
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
      onStep(describeTool('${uses.first['name']}'));
      if (uses.any((u) => writingTools.contains(u['name']))) wroteNotes = true;
      messages.add({
        'role': 'user',
        'content': [
          for (final use in uses) _run(use),
          for (final later in takeLater()) {'type': 'text', 'text': later},
        ],
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
    return answer.isEmpty ? 'The model sent no answer. Try again.' : answer;
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
