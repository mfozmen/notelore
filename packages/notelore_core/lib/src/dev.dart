/// The developer's command line (`bin/notelore_dev.dart`): runs the real agent
/// against a real provider on the `NOTELORE_HOME` sandbox and traces every
/// HTTP exchange, so a provider bug can be seen without the app.
///
///     notelore_dev signin              ChatGPT plan sign-in (opens the browser)
///     notelore_dev models              the plan's models
///     notelore_dev chat [--provider=chatgpt] [--model=<id>] <message...>
///     notelore_dev eval [--provider=…] [--model=…] [--cases=eval/cases.json]
///                                      the model eval (#325), on temp notes
///     notelore_dev distill [--provider=…] [--model=…] [--cases=…] [--out=train.jsonl]
///                                      a teacher's passing turns as training data (#327)
///
/// It refuses to run without `NOTELORE_HOME`, so the real notes are never
/// touched. Secrets live in `<state>/dev-secrets.json`, never the app's
/// keystore; traces in `<state>/trace/`, with tokens redacted.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'agent.dart';
import 'eval.dart';
import 'paths.dart';
import 'providers/base.dart';
import 'providers/chatgpt.dart';
import 'providers/chatgpt_auth.dart';
import 'providers/http.dart';
import 'providers/providers.dart';
import 'store/index.dart';
import 'tools.dart';

const _usage =
    'usage: notelore_dev signin | models | chat [--provider=<name>] [--model=<id>] <message>'
    ' | eval [--provider=<name>] [--model=<id>] [--cases=<file>] [--slim] [--greedy] [--runs=<n>]'
    ' | distill [--provider=<name>] [--model=<id>] [--cases=<file>] [--out=<file>] [--slim]'
    ' | reprompt --in=<file> --out=<file> [--slim]'
    ' (--slim: the prompt and tools of the model on the device;'
    ' --greedy: temperature 0, on Ollama; --runs: the set n times, eval only)';

/// A trace file's name for a run started at [time]: UTC to the microsecond,
/// always six digits, so names sort in time order (`toIso8601String()` drops
/// zero microseconds, and `.120Z` sorts after `.120345Z`).
String traceName(DateTime time) {
  final utc = time.toUtc();
  final second = utc.toIso8601String().substring(0, 19).replaceAll(':', '-');
  final micros = (utc.millisecond * 1000 + utc.microsecond).toString().padLeft(6, '0');
  return '$second.${micros}Z.log';
}

/// Runs one command; the exit code is 0, 1 (it failed) or 64 (bad usage).
Future<int> runDev(
  List<String> args, {
  required Map<String, String> environment,
  required Directory currentDirectory,
  required StringSink out,
  required Future<void> Function(Uri url) openBrowser,
  required http.Client client,
  DateTime Function() now = DateTime.now,
}) async {
  if ((environment['NOTELORE_HOME'] ?? '').isEmpty) {
    out.writeln('Set NOTELORE_HOME (e.g. .dev-home): notelore_dev never touches the real notes.');
    return 64;
  }
  final options = {
    for (final a in args)
      if (a.startsWith('--') && a.contains('='))
        a.substring(2, a.indexOf('=')): a.substring(a.indexOf('=') + 1),
  };
  final words = args.where((a) => !a.startsWith('--')).toList();
  final slim = args.contains('--slim');
  final runs = int.tryParse(options['runs'] ?? '1') ?? 0;
  final command = words.firstOrNull;
  final message = words.skip(1).join(' ');
  if (command == null ||
      !const {'signin', 'models', 'chat', 'eval', 'distill', 'reprompt'}.contains(command) ||
      (command == 'chat' && message.isEmpty) ||
      runs < 1 ||
      (runs > 1 && command != 'eval')) {
    out.writeln(_usage);
    return 64;
  }

  final paths = NotelorePaths.resolve(
    environment: environment,
    currentDirectory: currentDirectory,
    defaultNotes: currentDirectory, // unused: NOTELORE_HOME is set
    defaultState: currentDirectory,
  );
  final traceFile = File(p.join(paths.state.path, 'trace', traceName(now())))
    ..createSync(recursive: true);
  final traced = TracingClient(
    client,
    (entry) => traceFile.writeAsStringSync('$entry\n\n', mode: FileMode.append),
  );
  final secrets = File(p.join(paths.state.path, 'dev-secrets.json'));
  Map<String, Object?> stored() => secrets.existsSync()
      ? (jsonDecode(secrets.readAsStringSync()) as Map).cast()
      : <String, Object?>{};
  final auth = ChatGptAuth(
    openBrowser: openBrowser,
    read: (name) async => stored()[name] as String?,
    write: (name, value) async => secrets.writeAsStringSync(
      jsonEncode({...stored(), name: value}..removeWhere((_, v) => v == null)),
    ),
    client: traced,
  );

  try {
    switch (command) {
      case 'signin':
        await auth.signIn();
        out.writeln('Signed in with ChatGPT.');
      case 'models':
        out.writeln((await listChatGptModels(auth.token, client: traced)).join('\n'));
      case 'reprompt':
        _reprompt(
          File(p.join(currentDirectory.path, options['in'] ?? 'train.jsonl')),
          File(p.join(currentDirectory.path, options['out'] ?? 'train-reprompted.jsonl')),
          out,
          slim: slim,
        );
      case 'eval' || 'distill':
        final cases = File(p.join(currentDirectory.path, options['cases'] ?? 'eval/cases.json'));
        final keep = command == 'distill'
            ? File(p.join(currentDirectory.path, options['out'] ?? 'train.jsonl'))
            : null;
        await _eval(
          cases,
          () => _provider(
            options,
            environment,
            auth,
            traced,
            out,
            temperature: args.contains('--greedy') ? 0 : null,
          ),
          out,
          keep: keep,
          slim: slim,
          runs: runs,
          search: findProvider(options['provider'] ?? 'chatgpt').webSearch,
        );
      default:
        await _chat(message, options, environment, paths, auth, traced, out);
    }
    return 0;
  } on Object catch (error) {
    out.writeln('Error: $error');
    return 1;
  } finally {
    out.writeln('Trace: ${traceFile.path}');
    traced.close();
  }
}

/// Every example of [from] with today's prompt and tools ([slim] or full),
/// written to [to] (#327).
void _reprompt(File from, File to, StringSink out, {required bool slim}) {
  final lines = [
    for (final line in from.readAsLinesSync())
      if (line.trim().isNotEmpty)
        jsonEncode(reprompted((jsonDecode(line) as Map).cast(), slim: slim)),
  ];
  to.writeAsStringSync(lines.map((line) => '$line\n').join());
  out.writeln('${lines.length} examples with the current prompt in ${to.path}');
}

/// One agent turn on [message] with the provider and model [options] name
/// (the ChatGPT plan by default), printing the tools it called and its answer.
Future<void> _chat(
  String message,
  Map<String, String> options,
  Map<String, String> environment,
  NotelorePaths paths,
  ChatGptAuth auth,
  http.Client traced,
  StringSink out,
) async {
  final provider = await _provider(options, environment, auth, traced, out);
  final index = NoteIndex(p.join(paths.state.path, 'index.sqlite'), paths.notes.path);
  try {
    final agent = Agent(
      provider,
      Toolbox(paths.notes.path, index),
      timing: (entry) => out.writeln('⏱ $entry'),
    );
    final answer = await agent.ask(message);
    _printTools(agent.messages, out);
    out.writeln(answer);
  } finally {
    index.close();
  }
}

/// Every case in [cases] against the provider [open] makes once the file is
/// there, each said as it ends, then the report. With [keep], the passing
/// turns go there as training examples, one JSON line each, written as each
/// case ends; the finished case ids go to `<keep>.done`, so a run that was
/// stopped (hours in, out of memory) goes on where it was (#327). Without
/// that file a run starts [keep] over.
Future<void> _eval(
  File cases,
  Future<LlmProvider> Function() open,
  StringSink out, {
  File? keep,
  bool slim = false,
  bool search = false,
  int runs = 1,
}) async {
  if (!cases.existsSync()) throw StateError('no cases file at ${cases.path}');
  final provider = await open();
  final done = keep == null ? null : File('${keep.path}.done');
  final finished = keep == null ? const <String>{} : _resume(keep, done!);
  final runnable = _runnable(loadCases(cases.readAsStringSync()), search, out);
  final everyRun = <List<EvalResult>>[];
  // Per case: null when it failed, the reasons it was left out, or none when kept.
  final outcomes = <Set<TrainingIssue>?>[];
  for (var run = 0; run < runs; run++) {
    final results = <EvalResult>[];
    everyRun.add(results);
    for (final evalCase in runnable) {
      if (finished.contains(evalCase.id)) continue;
      final result = await runCase(evalCase, provider, slim: slim);
      results.add(result);
      final verdict = result.passed ? 'ok  ' : 'FAIL';
      out.writeln('$verdict ${evalCase.id} (${result.took.inMilliseconds} ms) ${result.tools}');
      if (keep != null) outcomes.add(_keepTurn(result, keep, done!));
    }
  }
  out.writeln(summarizeRuns(everyRun));
  if (keep == null) return;
  final results = everyRun.single; // distill runs once
  if (finished.isNotEmpty) out.writeln('skipped ${finished.length} already done in ${done!.path}');
  final kept = outcomes.where((issues) => issues != null && issues.isEmpty).length;
  out.writeln('kept $kept of ${results.length} in ${keep.path}');
  final excluded = outcomes.whereType<Set<TrainingIssue>>().where((issues) => issues.isNotEmpty);
  int count(TrainingIssue issue) => excluded.where((found) => found.contains(issue)).length;
  out.writeln(
    'excluded ${excluded.length} passing turns '
    '(tool errors: ${count(TrainingIssue.toolError)}; '
    'repeated calls: ${count(TrainingIssue.repeatedCall)}; '
    'counts may overlap)',
  );
}

/// The cases that mean something for a provider that can [search] or not: a
/// case that needs web search is left out where there is none (#478), and
/// [out] says how many.
List<EvalCase> _runnable(List<EvalCase> all, bool search, StringSink out) {
  final runnable = all.where((c) => c.runsWith(search: search)).toList();
  final left = all.length - runnable.length;
  if (left > 0) {
    out.writeln('left out $left ${left == 1 ? 'case that needs' : 'cases that need'} web search');
  }
  return runnable;
}

/// The case ids [done] marks finished (`<id>`, or `<id>\tkept` when it kept a
/// turn), with [keep] cut back to the turns those kept: a run stopped after
/// writing a turn but before marking its case leaves no duplicate. Without
/// [done], [keep] starts over.
Set<String> _resume(File keep, File done) {
  final records = done.existsSync() ? done.readAsLinesSync() : const <String>[];
  final lines = keep.existsSync() ? keep.readAsLinesSync() : const <String>[];
  final kept = records.where((record) => record.endsWith('\tkept')).length;
  if (records.isEmpty || lines.length > kept) {
    keep.writeAsStringSync(lines.take(kept).map((line) => '$line\n').join(), flush: true);
  }
  return {for (final record in records) record.split('\t').first};
}

/// Appends [result] to [keep] when it passed without detours, then marks its
/// case in [done]; null when it failed, else why it was left out (none: kept).
Set<TrainingIssue>? _keepTurn(EvalResult result, File keep, File done) {
  final issues = result.passed ? trainingIssues(result.messages) : null;
  final keeps = issues != null && issues.isEmpty;
  if (keeps) {
    keep.writeAsStringSync(
      '${jsonEncode(trainingExample(result))}\n',
      mode: FileMode.append,
      flush: true,
    );
  }
  final mark = keeps ? '\tkept' : '';
  done.writeAsStringSync('${result.evalCase.id}$mark\n', mode: FileMode.append, flush: true);
  return issues;
}

/// The provider and model [options] name (the ChatGPT plan by default), said on [out].
Future<LlmProvider> _provider(
  Map<String, String> options,
  Map<String, String> environment,
  ChatGptAuth auth,
  http.Client traced,
  StringSink out, {
  double? temperature,
}) async {
  final spec = findProvider(options['provider'] ?? 'chatgpt');
  final keyName = 'NOTELORE_${spec.name.toUpperCase()}_API_KEY';
  final key = environment[keyName];
  if (spec.requiresApiKey && key == null) throw StateError('set $keyName');
  final model =
      options['model'] ??
      (spec.name == 'chatgpt'
          ? (await listChatGptModels(auth.token, client: traced)).first
          : spec.defaultModel);
  out.writeln('[${spec.name} · $model]');
  return createProvider(
    spec,
    key,
    model: model,
    planToken: auth.token,
    client: traced,
    temperature: temperature,
    transport: (method, url, {headers = const {}, body, required timeout}) =>
        request(traced, method, url, headers: headers, body: body, timeout: timeout),
  );
}

void _printTools(List<Map<String, Object?>> messages, StringSink out) {
  for (final message in messages) {
    if (message['content'] case final List<Object?> blocks) {
      for (final block in blocks.cast<Map<Object?, Object?>>()) {
        switch (block['type']) {
          case 'tool_use':
            out.writeln('→ ${block['name']} ${jsonEncode(block['input'])}');
          case 'tool_result':
            final text = '${block['content']}';
            out.writeln('← ${text.length > 300 ? '${text.substring(0, 300)}…' : text}');
        }
      }
    }
  }
}

const _secretHeaders = {'authorization', 'x-api-key', 'x-goog-api-key', 'cookie'};

final _jsonSecret = RegExp(
  r'"(access_token|refresh_token|id_token|code_verifier|client_secret)"\s*:\s*"[^"]*"',
);
final _formSecret = RegExp(r'(^|&)(code|code_verifier|refresh_token|client_secret)=[^&]*');

/// [text] with token values replaced by `***`, in JSON and in form bodies.
String redact(String text) => text
    .replaceAllMapped(_jsonSecret, (m) => '"${m[1]}":"***"')
    .replaceAllMapped(_formSecret, (m) => '${m[1]}${m[2]}=***');

/// An HTTP client that logs each request and, once read, its response.
class TracingClient extends http.BaseClient {
  TracingClient(this._inner, this._log);

  final http.Client _inner;
  final void Function(String entry) _log;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final headers = [
      for (final MapEntry(:key, :value) in request.headers.entries)
        '$key: ${_secretHeaders.contains(key.toLowerCase()) ? '***' : value}',
    ];
    final body = request is http.Request ? request.body : '';
    _log('> ${request.method} ${request.url}\n${headers.join('\n')}\n${redact(body)}');
    final response = await _inner.send(request);
    final bytes = <int>[];
    var logged = false;
    void logBody() {
      if (logged) return;
      logged = true;
      _log(
        '< ${response.statusCode} ${request.url}\n'
        '${redact(utf8.decode(bytes, allowMalformed: true))}',
      );
    }

    // A reader may stop early (the plan provider does at response.completed),
    // so the body is logged on cancel as well as when it is done.
    late final StreamSubscription<List<int>> source;
    late final StreamController<List<int>> relay;
    relay = StreamController(
      onListen: () => source = response.stream.listen(
        (chunk) {
          bytes.addAll(chunk);
          relay.add(chunk);
        },
        onError: relay.addError,
        onDone: () {
          logBody();
          relay.close();
        },
      ),
      onCancel: () {
        logBody();
        return source.cancel();
      },
    );
    return http.StreamedResponse(
      relay.stream,
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}
