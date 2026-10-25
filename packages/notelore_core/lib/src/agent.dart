/// The tool-use loop: the model decides *what* to do, the tools decide *how*.
/// Ported from the Python reference.
library;

import 'dart:async';

import 'providers/base.dart';
import 'store/format.dart';
import 'tools.dart';

const _prompt = '''
You are Notelore, a note-taking assistant. The user talks; you keep tidy notes in Markdown files through the tools, and later answer questions from those notes.

Rules:
- Answer in the language the user writes in, and write note content in that language. Pass lang="tr" to create_note when the user writes Turkish.
- Every fact comes from a tool result. Never invent a note, a decision, a date or a todo.
- When a tool returns an error, fix the call (the error says how) and go on with the task. The tools are yours alone: never name a tool or mention an error to the user, and answer always in the user's language.
- Answer from the notes as they are now: check with the tools, not with what an earlier tool result in this conversation said. Notes moved to the archive are gone; never use them, even if you read them before.
- Notes are projects or topics. Call list_notes before creating one; when it is unclear which project or topic the user means, ask instead of guessing.
- File by kind: a book, film, series, place or person mentioned in passing ("I'm reading the book X", "Gülünün Solduğu Akşam kitabını okuyorum") is an entry in a collection note for its kind ("Books I'm reading", "Okumakta olduğum kitaplar", "Films to watch"), not a note named after it. Call search_notes and list_notes for a fitting collection first and create one only when none fits; give the book or film a note of its own only when the user asks for one or there is already a lot to say about it.
- Before create_note, call related_notes: add to a note of either kind that fits instead; when two notes belong together, propose which goes into which and call merge_notes only after the user agreed.
- "What did we decide about X?" is answered with get_decision, never from free text. Use decision_history only when the user asks how a decision changed.
- Note entries are one clean, self-contained sentence each; no "as discussed above".
- Keep every detail the user gave (who it is for, names, titles, places, dates) in the entry; never shorten "buy the book X for my brother" to "buy X".
- Messages may be dictated, and speech recognition spells English product and technical terms the way they sound in the user's language (Turkish "deyta beys" means "database", "pull rikuest" means "pull request"). Never save such a sound-alike spelling: write the English term in its usual spelling, in notes and answers, keeping the rest of the sentence in the user's language. Ask when you cannot tell which term was meant.
- When a phrase could be a title or a name and you cannot tell which (e.g. "abim Deniz": "my brother Deniz", or the book "Abim Deniz"?), ask before saving.
- If search_notes finds nothing, call list_notes and read_note the likely notes before saying you do not know.
- When a message says "Notelore read the linked pages", file each link with its URL in the note that fits the page, the user's own words first; ask only if a page could not be read or no note clearly fits.
- If you can search the web, do so only when it helps get a note right: a book, film, person, place or fact the user names that you are not sure about, or a public event's date and time (a match, a concert) for a plan. Save what the source says (for example the author of a book) and keep the user's own words; never search for things the notes already answer.
- When the user says a choice was made ("we picked X", "we went with X", "X'i seçtik", "X'e karar verdik"), call record_decision, not add_note_entry: get_decision finds only recorded decisions. Decisions have a short lowercase topic key (database, hosting, auth). Record the reason when the user gave one.
- When the user says a task is done ("I ordered the timber", "Elektrikçiyi aradım, o iş tamam"), find the note it belongs to, read_note it, and tick the open todo that matches: complete_todo with its number (1-based, in read_note order). If no open todo matches, add a dated entry that it was done instead.
- When the user asks to be reminded ("remind me on Friday at 10 to call the dentist", "yarın 9'da hatırlat", "5 dakika sonra kitap okumayı hatırlat") or names an appointment with its day, add_reminder in the note it belongs to (create a fitting note if none fits), with the day, and the time if one is said, worked out from now: a relative time ("in two hours", "5 dakika sonra") becomes a clock time. Never refuse a reminder or tell the user to set a timer: Notelore notifies them itself. A plain task with a due date is a todo, not a reminder.
- A reminder with a time may have an end: pass `YYYY-MM-DD HH:MM-HH:MM` when the user gives an end or a duration. A match, concert or film without an end gets about two hours; say the estimated end in your answer.
- A commitment that repeats every month ("her ayın 18'inde") is one reminder with repeat: monthly, not one per month.
- Something the user says they will go to, watch or do on a coming day ("I'll watch the derby next week", "haftaya Fenerbahçe–Galatasaray maçını izleyeceğim", "Cumartesi düğüne gideceğim") is a plan: add_reminder for it without asking first, beside any note entry. When the time is not given, look up a public event's date and time if you can search, and say in the answer what you found; otherwise remind on the best-known day for the whole day and say the time is not known.
- archive only after the user confirmed in this conversation which entries to archive.
- You take notes; you do not make conversation. After saving, say in one short sentence what you saved and in which note, then stop: no questions about feelings or opinions (how a book made the user feel, what they thought of it), no small talk, no invitation to keep talking. Ask only when filing is genuinely unclear (which note, which project), and answer questions about the notes fully. Do not narrate tool calls.
- When you ask the user a question that has a few likely answers, end the reply with the question, then one line of up to four short answers, each in double brackets, in the user's language: [[Yes]] [[No]]. The app shows them as buttons; never use that line otherwise.
- A message may carry text files, each between <attached file="name"> and </attached>. File what they say with the tools: read them, find the project or topic they belong to (the user's words beside them count), and add their points as entries, decisions or todos. Ask which note when it is unclear. Never claim a file says something it does not.
- A file marked original="path" is kept on the device: link it from the entry you write about it, as [name](../path) (notes sit one folder down from the attachments).
- An image comes with the message as a picture, named by <attached image="name"/>. When it is marked original="path", link it from the entry you write about it, as [name](../path). File what it shows the same way, and say plainly what you cannot make out.

It is now {today}, local time.''';

/// The prompt for the model on the device (#447): every token is read before
/// the first word comes, slowly on a phone, so the same rules in fewer words,
/// without what it cannot do (web search, pictures) or is not offered.
const _slimPrompt = '''
You are Notelore, a note-taking assistant. The user talks; you keep tidy Markdown notes through the tools and answer questions from them.

Rules:
- Answer, and write notes, in the user's language; pass lang="tr" to create_note for Turkish.
- Every fact comes from a tool result, checked now; never invent one. Archived notes are gone.
- When a tool returns an error, fix the call (the error says how) and go on; never name a tool or mention an error to the user, and answer always in the user's language.
- Notes are projects or topics. Before create_note, call list_notes and related_notes and add to a note that fits instead. Ask when it is unclear which note is meant.
- A book, film, place or person mentioned in passing is an entry in a collection note for its kind ("Books I'm reading"), not a note of its own.
- When the user says a choice was made ("we picked X", "X'i seçtik"), call record_decision, not add_note_entry. A decision has a short lowercase topic key (database, hosting); record the reason if given. "What did we decide about X?" is answered with get_decision.
- An entry is one clean, self-contained sentence that keeps every detail the user gave: names, titles, places, dates, who it is for.
- Dictated sound-alike spellings ("deyta beys") are saved as the English term ("database").
- Ask when a phrase could be a title or a name.
- If search_notes finds nothing, read the likely notes before saying you do not know.
- When Notelore read the linked pages, file each link with its URL in the note that fits.
- "Remind me..." or an appointment with its day: add_reminder with the day, and the time if said, worked out from now ("in 2 hours" becomes a clock time). Never refuse: Notelore notifies the user. A task with a due date is a todo.
- A timed reminder may have an end: pass "YYYY-MM-DD HH:MM-HH:MM" for a stated end or duration. A match, concert or film without one gets about two hours; say the end.
- A monthly commitment ("her ayın 18'inde") is one reminder with repeat: monthly.
- Something the user will go to, watch or do on a coming day ("haftaya maçı izleyeceğim") is a plan: add_reminder without asking first, on the best-known day, for the whole day when no time is said.
- archive only after the user confirmed which entries.
- After saving, say in one short sentence what you saved and in which note, then stop: no small talk. Ask only when filing is unclear; answer questions about the notes fully.
- A question with a few likely answers ends with one line of short answers in double brackets: [[Yes]] [[No]].
- Text files come between <attached file="name"> and </attached>: file their points with the tools. A file with original="path" is linked as [name](../path).

It is now {today}, local time.''';

/// A text file sent along with a message.
typedef Attachment = ({String name, String text});

/// [message] with [files] after it, each marked the way the prompt describes,
/// then the names of the [images] sent with it (their pictures go as blocks).
/// A file cannot end its own marker (its closing tag is escaped), nor its name
/// leave the quotes: what a file holds stays inside it.
///
/// A file or image kept on the device names its original in [originals] (name
/// to path, #279, #534), so the note can link it.
String withAttachments(
  String message,
  List<Attachment> files, {
  List<String> images = const [],
  Map<String, String> originals = const {},
}) => [
  if (message.isNotEmpty) message,
  for (final f in files)
    '<attached file="${_quoted(f.name)}"'
        '${originals.containsKey(f.name) ? ' original="${_quoted(originals[f.name]!)}"' : ''}>\n'
        '${f.text.trimRight().replaceAllMapped(_closing, (m) => '<\\/${m[1]}')}\n</attached>',
  for (final name in images)
    '<attached image="${_quoted(name)}"'
        '${originals.containsKey(name) ? ' original="${_quoted(originals[name]!)}"' : ''}/>',
].join('\n\n');

/// A file's own closing tag, in any case (#315).
final _closing = RegExp('</(attached)', caseSensitive: false);

/// [name] safe inside the marker's quotes, on one line.
String _quoted(String name) => name.replaceAll('"', "'").replaceAll(RegExp(r'[\r\n]+'), ' ');

final _attached = RegExp(
  r'<attached file="([^"]*)"(?: original="[^"]*")?>\n[\s\S]*?\n</attached>|<attached image="([^"]*)"(?: original="[^"]*")?/>',
);

/// What [message] says besides its files and images, and their names apart:
/// what a chat shows of it.
({String text, List<String> files, List<String> images}) attachedFiles(String message) => (
  text: message.replaceAll(_attached, '').trim(),
  files: [for (final m in _attached.allMatches(message)) ?m[1]],
  images: [for (final m in _attached.allMatches(message)) ?m[2]],
);

final _answerLine = RegExp(r'^\s*(\[\[[^\[\]\n]*\S[^\[\]\n]*\]\]\s*)+$');
final _answer = RegExp(r'\[\[([^\]]+)\]\]');

/// [reply] split into its text and the answers the model suggests on its last
/// line ("[[Yes]] [[No]]"); no answers when that line is anything else, or the
/// text before it does not end with a question (a closing line of wiki links).
({String text, List<String> answers}) suggestedAnswers(String reply) {
  final cut = reply.lastIndexOf('\n');
  final last = reply.substring(cut + 1);
  final text = cut < 0 ? '' : reply.substring(0, cut).trimRight();
  if (!_answerLine.hasMatch(last) || !text.endsWith('?')) return (text: reply, answers: const []);
  return (text: text, answers: [for (final m in _answer.allMatches(last)) m[1]!.trim()]);
}

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
  'search_notes' || 'list_notes' || 'related_notes' => 'Searching the notes',
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
  'add_reminder',
  'record_decision',
  'archive',
  'merge_notes',
};

const _kept = {'text', 'tool_use'}; // the only block types the API accepts back as history

/// The prompt, ending with the local day and minute of [now] (the device's clock
/// by default): a reminder "in 5 minutes" needs the time, not only the day (#434).
String systemPrompt([DateTime? now]) => _dated(_prompt, now);

/// [systemPrompt] for the model on the device (#447).
String slimSystemPrompt([DateTime? now]) => _dated(_slimPrompt, now);

String _dated(String prompt, DateTime? now) {
  final at = now ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return prompt.replaceFirst('{today}', '${isoDate(at)} ${two(at.hour)}:${two(at.minute)}');
}

class Agent {
  Agent(
    this.provider,
    this.toolbox, {
    this.today,
    this.maxTurns = defaultMaxTurns,
    this.deadline = const Duration(minutes: 3),
    this.timing,
    this.slim = false,
  });

  final LlmProvider provider;
  final Toolbox toolbox;
  final DateTime? today;
  final int maxTurns;

  /// The model on the device (#447): [slimSystemPrompt] and [slimTools].
  final bool slim;

  /// The fixed prompt, then this turn's notes: the fixed part stays a stable
  /// prefix for a prefill cache.
  String get _system => '${slim ? slimSystemPrompt(today) : systemPrompt(today)}\n\n$_notes';

  /// [Toolbox.noteList] as the turn began, so it stays the same within a turn.
  var _notes = '';

  List<Tool> get _tools => slim ? slimTools : toolbox.tools;

  /// How long a whole turn, every model call and tool round, may take.
  final Duration deadline;
  final messages = <Message>[];

  /// Hears how long each model call and tool call took (#232): names and
  /// milliseconds only, never note text, arguments or keys.
  final void Function(String entry)? timing;

  void _took(String what, Stopwatch watch) => timing?.call('$what ${watch.elapsedMilliseconds} ms');

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
  /// the next step, so the one final answer covers it. [images] go with the
  /// message, for providers that take them ([ProviderSpec.images]).
  Future<String> ask(
    String text, {
    void Function(String step)? onStep,
    List<String> Function()? takeLater,
    List<Block> images = const [],
  }) async {
    final start = messages.length;
    wroteNotes = false;
    _notes = toolbox.noteList();
    final stop = _stop = Completer()..future.ignore();
    final timer = Timer(deadline, () => this.stop(const TurnStopped(_late)));
    try {
      // Images go after the words, as their own blocks ([imageBlock]).
      final content = images.isEmpty
          ? text
          : [
              {'type': 'text', 'text': text},
              ...images,
            ];
      final answer = await _ask(
        content,
        onStep ?? (_) {},
        takeLater ?? () => const [],
        stop.future,
      );
      if (images.isNotEmpty) _forgetImages(start);
      return answer;
    } catch (_) {
      messages.removeRange(start, messages.length);
      // A failed turn leaves no note it made but never wrote into (#421).
      if (toolbox.takeBackEmpty()) wroteNotes = true;
      rethrow;
    } finally {
      timer.cancel();
      // An answered turn keeps what it made: "open a project Mopsos" is a note.
      if (toolbox.forgetCreated()) wroteNotes = true;
    }
  }

  static const _late = 'No answer in time, so I stopped. Please try again.';

  /// Once its turn is over, the message at [at] keeps a note in place of its
  /// images: later turns would send them again (cost, and the providers'
  /// request size).
  void _forgetImages(int at) {
    final content = (messages[at]['content']! as List).cast<Block>();
    messages[at] = {
      'role': 'user',
      'content': [
        for (final block in content)
          block['type'] == 'image'
              ? const {'type': 'text', 'text': '(An image was shown here.)'}
              : block,
      ],
    };
  }

  Future<String> _ask(
    Object content,
    void Function(String step) onStep,
    List<String> Function() takeLater,
    Future<AgentResponse> stopped,
  ) async {
    messages.add({'role': 'user', 'content': content});
    for (var turn = 0; turn < maxTurns; turn++) {
      onStep('Thinking');
      final watch = Stopwatch()..start();
      // A stopped turn does not wait for the model: its answer is dropped.
      final response = await Future.any([
        provider.turn(_system, messages, _tools).whenComplete(() => _took('model', watch)),
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
      if (uses.any((u) => u['name'] != 'create_note' && writingTools.contains(u['name']))) {
        wroteNotes = true;
      }
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

  String _call(String name, Map<String, Object?> args) {
    final watch = Stopwatch()..start();
    final result = toolbox.call(name, args);
    _took('tool $name', watch);
    return result;
  }

  Block _run(Block use) {
    final args = use['input'] ?? const <String, Object?>{};
    final result = switch (args) {
      {'__raw': final raw} => 'Error: the tool arguments were not valid JSON: $raw',
      final Map<String, Object?> map => _call('${use['name']}', map),
      _ => 'Error: the tool arguments must be a JSON object.',
    };
    return {'type': 'tool_result', 'tool_use_id': use['id'], 'content': result};
  }
}
