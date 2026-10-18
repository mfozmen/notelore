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
      notes = {
        for (final MapEntry(:key, :value) in ((json['notes'] as Map?) ?? {}).entries)
          '$key': (value as List).cast<String>(),
      };

  /// Tool names that must be called, in any order.
  final List<String> tools;

  /// Facts the final answer must contain (case-insensitive).
  final List<String> answer;

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
      expect = Expectation.fromJson((json['expect']! as Map).cast());

  final String id;
  final String kind;
  final String lang;
  final String message;

  /// Relative path (`/`) -> note text, written before the turn.
  final Map<String, String> notes;
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
  });

  final EvalCase evalCase;
  final List<String> tools;
  final List<String> changed;
  final String answer;
  final List<String> problems;
  final Duration took;

  /// The whole exchange, for a training example of a passing turn (#327).
  final List<Message> messages;

  bool get passed => problems.isEmpty;
}

/// Runs [evalCase] once with [provider] on a fresh temp notes folder.
Future<EvalResult> runCase(EvalCase evalCase, LlmProvider provider) async {
  final dir = Directory.systemTemp.createTempSync('notelore_eval_');
  final root = p.join(dir.path, 'notes');
  final index = NoteIndex(p.join(dir.path, 'state', 'index.sqlite'), root);
  final watch = Stopwatch()..start();
  try {
    _write(root, evalCase.notes);
    final before = _files(root);
    final agent = Agent(provider, Toolbox(root, index, today: evalToday), today: evalNow);
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
    if (problems.isEmpty) {
      problems.addAll([
        ..._missingTools(evalCase.expect, tools),
        ..._strayWrites(evalCase.expect, changed),
        ..._missingFacts(evalCase.expect, changed, after),
        for (final fact in evalCase.expect.answer)
          if (!_has(answer, fact)) 'the answer lacks "$fact"',
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
    );
  } finally {
    index.close();
    dir.deleteSync(recursive: true);
  }
}

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

/// [result]'s turn as one chat transcript with tool calls, the shape Qwen's
/// and most open models' chat templates train on (#327).
Map<String, Object?> trainingExample(EvalResult result) => {
  'messages': [
    {'role': 'system', 'content': systemPrompt(evalNow)},
    ...toOllama(result.messages),
  ],
  'tools': functionTools(noteTools),
};

enum TrainingIssue { toolError, repeatedCall }

/// Problems in a passing turn that would teach the student a bad tool path.
Set<TrainingIssue> trainingIssues(List<Message> messages) {
  final issues = <TrainingIssue>{};
  final calls = <List<Object?>>[];
  const equality = DeepCollectionEquality();
  for (final message in messages) {
    if (message['content'] case final List<Object?> blocks) {
      for (final block in blocks.cast<Map<Object?, Object?>>()) {
        if (block['type'] == 'tool_result' &&
            block['content'] is String &&
            (block['content']! as String).startsWith('Error')) {
          issues.add(TrainingIssue.toolError);
        }
        if (block['type'] == 'tool_use') {
          final call = [block['name'], block['input']];
          if (calls.any((seen) => equality.equals(seen, call))) {
            issues.add(TrainingIssue.repeatedCall);
          }
          calls.add(call);
        }
      }
    }
  }
  return issues;
}

bool _has(String text, String fact) => text.toLowerCase().contains(fact.toLowerCase());

/// Every file under [root] as relative path (`/`) -> text.
Map<String, String> _files(String root) => {
  for (final file in Directory(root).listSync(recursive: true).whereType<File>())
    p.posix.joinAll(p.split(p.relative(file.path, from: root))): file.readAsStringSync(),
};

/// Accuracy per kind and overall, then every failure with its reasons.
String summarize(List<EvalResult> results) {
  String line(String name, Iterable<EvalResult> group) {
    final passed = group.where((r) => r.passed).length;
    if (group.isEmpty) return '$name: 0/0';
    return '$name: $passed/${group.length} (${(100 * passed / group.length).round()}%)';
  }

  final kinds = {for (final r in results) r.evalCase.kind}.toList()..sort();
  return [
    for (final kind in kinds) line(kind, results.where((r) => r.evalCase.kind == kind)),
    line('all', results),
    for (final r in results)
      if (!r.passed) 'FAIL ${r.evalCase.id}: ${r.problems.join('; ')}',
  ].join('\n');
}
