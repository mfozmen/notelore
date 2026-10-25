/// The model eval (#325): realistic note-taking turns with expected outcomes,
/// run against any [LlmProvider] on temp notes, to choose and tune the model
/// Notelore runs on the device (#227). Never touches real notes.
///
/// A case is a few notes, one user message and what should follow: tools that
/// must be called, the notes that may change and the facts they must then
/// hold (keyed by a path pattern, since a model names a new note its own way),
/// and facts the answer must contain. Any other change to the notes fails it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

import 'agent.dart';
import 'providers/base.dart';
import 'providers/ollama.dart';
import 'providers/openai.dart';
import 'store/index.dart';
import 'tools.dart';

/// The day every case runs on, so dates in notes and answers are stable.
final evalToday = DateTime(2026, 10, 18);

/// The minute the model is told it is, so "in 5 minutes" has one answer (#434).
final evalNow = DateTime(2026, 10, 18, 14);

class Expectation {
  Expectation.fromJson(Map<String, Object?> json)
    : tools = [...?(json['tools'] as List?)?.cast<String>()],
      answer = [...?(json['answer'] as List?)?.cast<String>()],
      answerNot = [...?(json['answer_not'] as List?)?.cast<String>()],
      linesNot = [...?(json['lines_not'] as List?)?.cast<String>()],
      notes = {
        for (final MapEntry(:key, :value) in ((json['notes'] as Map?) ?? {}).entries)
          '$key': (value as List).cast<String>(),
      };

  /// Tool names that must be called, in any order.
  final List<String> tools;

  /// Facts the final answer must contain (case-insensitive).
  final List<String> answer;

  /// Words it must not (case-insensitive): a tool's name, an apology (#474).
  final List<String> answerNot;

  /// Patterns no line of a changed note may match: a reminder written as a
  /// sentence instead of a calendar title (#499).
  final List<String> linesNot;

  /// Path pattern (relative, `/`) -> facts a changed note matching it must hold.
  /// Only notes matching one of these may change.
  final Map<String, List<String>> notes;
}

class EvalCase {
  EvalCase.fromJson(Map<String, Object?> json, {Map<Object?, Object?> shared = const {}})
    : id = json['id']! as String,
      kind = json['kind']! as String,
      lang = json['lang']! as String,
      message = json['message']! as String,
      notes = ((json['notes'] as Map?) ?? shared).cast<String, String>(),
      failFirstCall = json['fail_first_call'] == true,
      search = (json['search'] as List?)?.cast<String>(),
      expect = Expectation.fromJson((json['expect']! as Map).cast());

  final String id;
  final String kind;
  final String lang;
  final String message;

  /// Relative path (`/`) -> note text, written before the turn.
  final Map<String, String> notes;

  /// The turn's first tool call gets an error: the model must fix it and go
  /// on, in the user's language, never hand the error to the user (#474).
  final bool failFirstCall;

  /// What a web search finds in this case's world (#478): the model gets a
  /// `web_search` that answers with it, as a provider with search would, but
  /// the same every run and on the eval's own day. Run only where the provider
  /// can search ([runsWith]).
  final List<String>? search;

  /// Whether this case means anything for a provider that can [search] or not.
  bool runsWith({required bool search}) => search || this.search == null;
  final Expectation expect;
}

/// The cases of a file: a list, or `{notes, cases}` where every case starts
/// from the shared notes unless it brings its own.
List<EvalCase> loadCases(String json) {
  final (shared, cases) = switch (jsonDecode(json)) {
    {'notes': final Map<Object?, Object?> notes, 'cases': final List<Object?> cases} => (
      notes,
      cases,
    ),
    final List<Object?> cases => (const <Object?, Object?>{}, cases),
    _ => throw const FormatException('expected a list of cases, or {notes, cases}'),
  };
  return [for (final item in cases) EvalCase.fromJson((item! as Map).cast(), shared: shared)];
}

class EvalResult {
  EvalResult(
    this.evalCase,
    this.tools,
    this.changed,
    this.answer,
    this.problems,
    this.took, {
    this.messages = const [],
    this.slim = false,
    this.action = '',
  });

  final EvalCase evalCase;
  final List<String> tools;
  final List<String> changed;
  final String answer;
  final List<String> problems;
  final Duration took;

  /// The whole exchange, for a training example of a passing turn (#327).
  final List<Message> messages;

  /// Asked with the prompt and tools of the model on the device (#447).
  final bool slim;

  /// What the turn did first: the write it stopped at, `create_note` when it
  /// only made a note, `ask` for a question back, or `none` (#598).
  final String action;

  /// What it should have done first, in the same terms.
  String get wanted => wantedAction(evalCase);

  bool get passed => problems.isEmpty;
}

/// The first write [evalCase] calls for (not counting a note made for it), a
/// new note's `create_note`, `ask` for an unclear message, or `none`.
String wantedAction(EvalCase evalCase) {
  final writes = evalCase.expect.tools.where(writingTools.contains);
  return switch (evalCase) {
    _ when writes.any((t) => t != 'create_note') => writes.firstWhere((t) => t != 'create_note'),
    EvalCase(kind: 'new-note') => 'create_note',
    EvalCase(kind: 'unclear') => 'ask',
    _ when evalCase.expect.notes.isNotEmpty => 'add_note_entry',
    _ => 'none',
  };
}

String _action(List<String> tools, String? stoppedAt, String answer) {
  if (stoppedAt != null) return stoppedAt;
  if (tools.contains('create_note')) return 'create_note';
  return answer.contains('?') ? 'ask' : 'none';
}

/// For the cases that failed: how often each wanted first action met each
/// done one, most often first (#598). Empty when none failed.
String confusion(List<EvalResult> results) {
  final counts = <String, int>{};
  for (final r in results.where((r) => !r.passed)) {
    counts.update('${r.wanted} → ${r.action}', (n) => n + 1, ifAbsent: () => 1);
  }
  if (counts.isEmpty) return '';
  final rows = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return [
    'wanted → done, failed cases:',
    for (final row in rows) '  ${row.key}: ${row.value}',
  ].join('\n');
}

/// Ends the turn once a write other than making a note has succeeded, so a
/// run scores the first decision only and skips the rest (#598).
class _UntilWrite implements LlmProvider {
  _UntilWrite(this._inner);

  final LlmProvider _inner;
  String? stoppedAt;

  @override
  String get model => _inner.model;

  @override
  Future<AgentResponse> turn(String system, List<Message> messages, List<Tool> tools) async {
    stoppedAt = _succeededWrite(messages);
    if (stoppedAt != null) return const AgentResponse([], 'end_turn');
    return _inner.turn(system, messages, tools);
  }
}

/// The write of the last step that did not fail, if any, besides create_note.
String? _succeededWrite(List<Message> messages) {
  if (messages.length < 2) return null;
  final uses = {
    for (final b in _blocks(messages[messages.length - 2]))
      if (b['type'] == 'tool_use') b['id']: '${b['name']}',
  };
  for (final b in _blocks(messages.last)) {
    final name = uses[b['tool_use_id']];
    final ok = b['type'] == 'tool_result' && !'${b['content']}'.startsWith('Error');
    if (ok && name != null && name != 'create_note' && writingTools.contains(name)) return name;
  }
  return null;
}

Iterable<Map<Object?, Object?>> _blocks(Message message) => switch (message['content']) {
  final List<Object?> blocks => blocks.cast<Map<Object?, Object?>>(),
  _ => const [],
};

/// Runs [evalCase] once with [provider] on a fresh temp notes folder; [slim]
/// as the model on the device asks (#447); with [firstWrite], only until its
/// first write, which is all that is scored then (#598).
Future<EvalResult> runCase(
  EvalCase evalCase,
  LlmProvider provider, {
  bool slim = false,
  bool firstWrite = false,
}) async {
  final until = firstWrite ? _UntilWrite(provider) : null;
  final dir = Directory.systemTemp.createTempSync('notelore_eval_');
  final root = p.join(dir.path, 'notes');
  final index = NoteIndex(p.join(dir.path, 'state', 'index.sqlite'), root);
  final watch = Stopwatch()..start();
  try {
    _write(root, evalCase.notes);
    final before = _files(root);
    final agent = Agent(
      until ?? provider,
      switch (evalCase) {
        EvalCase(failFirstCall: true) => _FailsOnce(root, index, today: evalToday),
        EvalCase(search: final found?) => _Searches(root, index, found, today: evalToday),
        _ => Toolbox(root, index, today: evalToday),
      },
      today: evalNow,
      slim: slim,
    );
    var answer = '';
    final problems = <String>[];
    try {
      answer = await agent.ask(evalCase.message);
    } on Object catch (error) {
      problems.add('error: $error');
    }
    final after = _files(root);
    final changed = _changed(before, after);
    final tools = _toolsCalled(agent.messages);
    final stoppedAt = until?.stoppedAt;
    if (problems.isEmpty) {
      problems.addAll([
        ..._missingTools(evalCase.expect, tools),
        ..._strayWrites(evalCase.expect, changed),
        ..._missingFacts(evalCase.expect, changed, after),
        ..._badLines(evalCase.expect, changed, after),
        // A turn stopped at its write has no answer to score.
        if (stoppedAt == null) ...[
          ..._answerProblems(evalCase.expect, answer),
          ?_wrongLanguage(evalCase.lang, answer),
        ],
      ]);
    }
    return EvalResult(
      evalCase,
      tools,
      changed,
      answer,
      problems,
      watch.elapsed,
      messages: agent.messages,
      slim: slim,
      action: _action(tools, stoppedAt, answer),
    );
  } finally {
    index.close();
    dir.deleteSync(recursive: true);
  }
}

/// A toolbox whose first call fails, as one would on a bad argument.
class _FailsOnce extends Toolbox {
  _FailsOnce(super.root, super.index, {super.today});

  var _failed = false;

  @override
  String call(String name, Map<String, Object?> args) {
    if (_failed) return super.call(name, args);
    _failed = true;
    return 'Error: $name could not run this time. Call it again.';
  }
}

/// A toolbox with the web search a case's world answers ([EvalCase.search]).
class _Searches extends Toolbox {
  _Searches(super.root, super.index, this.found, {super.today});

  final List<String> found;

  static const _search = Tool('web_search', 'Search the web: the results as text.', {
    'type': 'object',
    'properties': {
      'query': {'type': 'string'},
    },
    'required': ['query'],
  });

  @override
  List<Tool> get tools => [...super.tools, _search];

  @override
  String call(String name, Map<String, Object?> args) =>
      name == _search.name ? found.join('\n') : super.call(name, args);
}

/// The error a case injects ([EvalCase.failFirstCall]), which no real tool
/// gives: training tells it from a real one, as recovering from it is the
/// lesson, not a detour.
final _injectedError = RegExp(r'^Error: \w+ could not run this time\. Call it again\.$');

bool _injected(Object? content) => content is String && _injectedError.hasMatch(content);

void _write(String root, Map<String, String> notes) {
  Directory(root).createSync(recursive: true);
  for (final MapEntry(:key, :value) in notes.entries) {
    File(p.joinAll([root, ...key.split('/')]))
      ..createSync(recursive: true)
      ..writeAsStringSync(value);
  }
}

/// The paths added, removed or changed, sorted.
List<String> _changed(Map<String, String> before, Map<String, String> after) => {
  for (final path in {...before.keys, ...after.keys})
    if (before[path] != after[path]) path,
}.toList()..sort();

/// The tools the turn called, in order.
List<String> _toolsCalled(List<Message> messages) => [
  for (final message in messages)
    if (message['content'] case final List<Object?> blocks)
      for (final block in blocks.cast<Map<Object?, Object?>>())
        if (block['type'] == 'tool_use') '${block['name']}',
];

Iterable<String> _missingTools(Expectation expect, List<String> tools) => [
  for (final tool in expect.tools)
    if (!tools.contains(tool)) 'did not call $tool',
];

Iterable<String> _strayWrites(Expectation expect, List<String> changed) {
  final patterns = [for (final key in expect.notes.keys) RegExp(key)];
  return [
    for (final path in changed)
      if (!patterns.any((pattern) => pattern.hasMatch(path)))
        'wrote $path, which it should not have',
  ];
}

Iterable<String> _missingFacts(
  Expectation expect,
  List<String> changed,
  Map<String, String> after,
) => [
  for (final MapEntry(:key, :value) in expect.notes.entries)
    for (final fact in value)
      if (!changed.any((path) => RegExp(key).hasMatch(path) && _has(after[path] ?? '', fact)))
        'no changed note matching $key contains "$fact"',
];

Iterable<String> _badLines(Expectation expect, List<String> changed, Map<String, String> after) => [
  for (final pattern in expect.linesNot)
    for (final path in changed)
      if (RegExp(pattern, multiLine: true).hasMatch(after[path] ?? ''))
        '$path has a line matching $pattern',
];

Iterable<String> _answerProblems(Expectation expect, String answer) => [
  for (final fact in expect.answer)
    if (!_has(answer, fact)) 'the answer lacks "$fact"',
  for (final word in expect.answerNot)
    if (_has(answer, word)) 'the answer has "$word"',
];

String? _wrongLanguage(String lang, String answer) => switch (answerLanguage(answer)) {
  final said? when said != lang => 'the answer is in $said, not $lang',
  _ => null,
};

const _englishWords = {
  'the', 'a', 'an', 'and', 'to', 'of', 'in', 'on', 'for', 'with', 'is', 'are', 'was', 'it', //
  'i', "i've", "i'll", 'you', 'your', 'this', 'that', 'what', 'which', 'do', 'did', 'have',
};

const _turkishWords = {
  've', 'bir', 'bu', 'şu', 'için', 'ile', 'da', 'de', 'mi', 'mı', 'mu', 'mü', 'ne', 'olarak', //
  'ekledim', 'kaydettim', 'notuna', 'notunu', 'hangi', 'nasıl', 'var', 'yok', 'yani', 'değil',
};

/// `en` or `tr` by which language's small words [answer] has more of, quoted
/// text left out (a Turkish title in an English answer); null when neither.
String? answerLanguage(String answer) {
  final unquoted = answer.replaceAll(RegExp(r'"[^"]*"|“[^”]*”|`[^`]*`'), ' ');
  final words = RegExp(
    r"[\p{L}']+",
    unicode: true,
  ).allMatches(unquoted.toLowerCase()).map((m) => m[0]!);
  final english = words.where(_englishWords.contains).length;
  final turkish = words.where(_turkishWords.contains).length;
  if (english > turkish) return 'en';
  if (turkish > english) return 'tr';
  return null;
}

/// [result]'s turn as one chat transcript with tool calls, the shape Qwen's
/// and most open models' chat templates train on (#327).
Map<String, Object?> trainingExample(EvalResult result) => {
  'messages': [
    {'role': 'system', 'content': result.slim ? slimSystemPrompt(evalNow) : systemPrompt(evalNow)},
    ...toOllama(collapseRepeatedReads(result.messages)),
  ],
  'tools': functionTools(result.slim ? slimTools : noteTools),
};

/// [example] (a line of a training file) with today's system prompt and tools,
/// [slim] or full, and its turns as they were: one file then teaches one
/// version of the rules, however its examples were made.
Map<String, Object?> reprompted(Map<String, Object?> example, {bool slim = false}) {
  final messages = (example['messages']! as List).cast<Map<String, Object?>>();
  return {
    ...example,
    'messages': [
      {'role': 'system', 'content': slim ? slimSystemPrompt(evalNow) : systemPrompt(evalNow)},
      ...messages.where((m) => m['role'] != 'system'),
    ],
    'tools': functionTools(slim ? slimTools : noteTools),
  };
}

/// [messages] without each read that repeats an earlier one, same tool, same
/// arguments, same result (a second identical list_notes, say): it taught
/// nothing, so it goes with its result, and with its step when it was the
/// step's only call. A write, or a read that answered otherwise, stays.
List<Message> collapseRepeatedReads(List<Message> messages) {
  final dropped = _repeatedReads(messages);
  return [for (final message in messages) ?_without(message, dropped)];
}

/// The ids of the reads [collapseRepeatedReads] drops. A write in between
/// does not matter: the same result means the repeat still learned nothing.
Set<Object?> _repeatedReads(List<Message> messages) {
  const equality = DeepCollectionEquality();
  final results = {
    for (final block in _trainingBlocks(messages))
      if (block['type'] == 'tool_result') block['tool_use_id']: block['content'],
  };
  final seen = <List<Object?>>[];
  final dropped = <Object?>{};
  for (final block in _trainingBlocks(messages)) {
    if (block['type'] != 'tool_use' || !results.containsKey(block['id'] ?? _noId)) continue;
    final call = [block['name'], block['input'], results[block['id']]];
    final read = !writingTools.contains(block['name']);
    if (read && seen.any((earlier) => equality.equals(earlier, call))) dropped.add(block['id']);
    seen.add(call);
  }
  return dropped;
}

/// Matches no result: a call without an id is never dropped.
const _noId = Object();

/// [message] without the [dropped] calls and their results; none when nothing
/// is left, or when every call of its step went (its words go with them).
Message? _without(Message message, Set<Object?> dropped) {
  final blocks = message['content'];
  if (blocks is! List<Object?>) return message;
  bool gone(Object? block) =>
      block is Map &&
      dropped.contains(block['type'] == 'tool_use' ? block['id'] : block['tool_use_id']);
  final calls = blocks.where((b) => b is Map && b['type'] == 'tool_use');
  if (calls.isNotEmpty && calls.every(gone)) return null;
  final left = blocks.where((b) => !gone(b)).toList();
  return left.isEmpty ? null : {...message, 'content': left};
}

/// Reasons a scored-passing teacher turn is excluded from distillation.
enum TrainingIssue { toolError, repeatedCall }

/// Problems in a passing turn that would teach the student a bad tool path.
/// [Toolbox.call] and [Agent] mark tool failures with an `Error:` prefix.
Set<TrainingIssue> trainingIssues(List<Message> messages) {
  final issues = <TrainingIssue>{};
  final calls = <List<Object?>>[];
  const equality = DeepCollectionEquality();
  final blocks = _trainingBlocks(collapseRepeatedReads(messages)).toList();
  // The call a case made fail on purpose: its retry is no repeat.
  final injected = {
    for (final block in blocks)
      if (block['type'] == 'tool_result' && _injected(block['content'])) block['tool_use_id'],
  };
  for (final block in blocks) {
    if (block['type'] == 'tool_result' &&
        block['content'] is String &&
        !_injected(block['content']) &&
        (block['content']! as String).toLowerCase().startsWith('error')) {
      issues.add(TrainingIssue.toolError);
    }
    if (block['type'] == 'tool_use' && !injected.contains(block['id'])) {
      final call = [block['name'], block['input']];
      if (calls.any((seen) => equality.equals(seen, call))) {
        issues.add(TrainingIssue.repeatedCall);
      }
      calls.add(call);
    }
  }
  return issues;
}

Iterable<Map<Object?, Object?>> _trainingBlocks(List<Message> messages) sync* {
  for (final message in messages) {
    if (message['content'] case final List<Object?> blocks) {
      yield* blocks.cast<Map<Object?, Object?>>();
    }
  }
}

bool _has(String text, String fact) => text.toLowerCase().contains(fact.toLowerCase());

/// Every file under [root] as relative path (`/`) -> text.
Map<String, String> _files(String root) => {
  for (final file in Directory(root).listSync(recursive: true).whereType<File>())
    p.posix.joinAll(p.split(p.relative(file.path, from: root))): file.readAsStringSync(),
};

/// Each run's total, then [summarize] over every run: a kind's share is its
/// mean (#597). One run reads as [summarize] alone.
String summarizeRuns(List<List<EvalResult>> runs) {
  final all = runs.expand((run) => run).toList();
  if (runs.length == 1) return summarize(all);
  return [
    for (final (i, run) in runs.indexed) 'run ${i + 1}: ${_share(run)}',
    summarize(all),
  ].join('\n');
}

String _share(Iterable<EvalResult> group) {
  final passed = group.where((r) => r.passed).length;
  return '$passed/${group.length} (${(100 * passed / group.length).round()}%)';
}

/// Accuracy per kind and overall, then every failure with its reasons.
String summarize(List<EvalResult> results) {
  String line(String name, Iterable<EvalResult> group) =>
      group.isEmpty ? '$name: 0/0' : '$name: ${_share(group)}';

  final kinds = {for (final r in results) r.evalCase.kind}.toList()..sort();
  return [
    for (final kind in kinds) line(kind, results.where((r) => r.evalCase.kind == kind)),
    line('all', results),
    for (final r in results)
      if (!r.passed) 'FAIL ${r.evalCase.id}: ${r.problems.join('; ')}',
  ].join('\n');
}
