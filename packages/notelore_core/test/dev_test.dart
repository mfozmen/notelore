import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notelore_core/src/dev.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

http.Response events(List<Map<String, Object?>> list) => http.Response(
  [for (final e in list) 'data: ${jsonEncode(e)}\n\n'].join(),
  200,
  headers: {'content-type': 'text/event-stream; charset=utf-8'},
);

Map<String, Object?> done(List<Object?> output) => {
  'type': 'response.completed',
  'response': {'status': 'completed', 'output': output},
};

void main() {
  late Directory temp;
  late StringBuffer out;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('notelore-dev');
    out = StringBuffer();
  });
  tearDown(() => temp.deleteSync(recursive: true));

  Future<int> run(
    List<String> args, {
    http.Client? client,
    Map<String, String>? environment,
    List<Uri>? opened,
    DateTime Function()? now,
  }) => runDev(
    args,
    environment: environment ?? {'NOTELORE_HOME': 'home'},
    currentDirectory: temp,
    out: out,
    openBrowser: (url) async => opened?.add(url),
    client: client ?? MockClient((_) async => http.Response('', 500)),
    now: now ?? DateTime.now,
  );

  String home(String rel) => p.join(temp.path, 'home', rel);

  void signedIn() {
    File(home('state/dev-secrets.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'client_id': 'oaiapp_1', 'refresh_token': 'r1'}));
  }

  /// The newest trace.
  String trace() {
    final files = Directory(home('state/trace')).listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return files.last.readAsStringSync();
  }

  test('trace names sort in time order, also on a whole millisecond (regression)', () async {
    // toIso8601String() drops zero microseconds (".120Z" vs ".120345Z"), so the
    // earlier run used to sort last and trace() read the wrong, empty file.
    final times = [
      DateTime.utc(2026, 10, 17, 17, 34, 45, 120),
      DateTime.utc(2026, 10, 17, 17, 34, 45, 120, 345),
    ];
    expect(await run(['chat', '--provider=openai', 'hi'], now: () => times[0]), 1); // no key
    expect(
      await run(
        ['chat', '--provider=openai', 'hi'],
        environment: {'NOTELORE_HOME': 'home', 'NOTELORE_OPENAI_API_KEY': 'sk'},
        now: () => times[1],
        client: MockClient((_) async => http.Response('', 500)),
      ),
      1,
    );
    final names = Directory(home('state/trace')).listSync().map((f) => p.basename(f.path)).toList()
      ..sort();
    expect(names, ['2026-10-17T17-34-45.120000Z.log', '2026-10-17T17-34-45.120345Z.log']);
    expect(trace(), contains('POST')); // the newest run's trace, not the empty one
  });

  test('refuses to run without NOTELORE_HOME: never the real notes', () async {
    expect(await run(['chat', 'hi'], environment: {}), 64);
    expect('$out', contains('NOTELORE_HOME'));
  });

  test('an unknown command or no message prints the usage', () async {
    expect(await run([]), 64);
    expect(await run(['dance']), 64);
    expect(await run(['chat']), 64);
    expect('$out', contains('usage: notelore_dev'));
  });

  test('chat: one real agent turn on the ChatGPT plan, tools shown, all traced', () async {
    signedIn();
    final requests = <String>[];
    var turn = 0;
    final client = MockClient((request) async {
      requests.add(request.url.path);
      if (request.url.path.endsWith('/oauth/token')) {
        return http.Response(
          jsonEncode({'access_token': 'a1', 'expires_in': 3600, 'refresh_token': 'r2'}),
          200,
        );
      }
      if (request.url.path == '/v1/models') {
        return http.Response(
          jsonEncode({
            'models': [
              {'slug': 'gpt-new', 'visibility': 'list'},
            ],
          }),
          200,
        );
      }
      expect((jsonDecode(request.body) as Map)['model'], 'gpt-new');
      return events([
        if (turn++ == 0)
          done([
            {'type': 'function_call', 'call_id': 'c1', 'name': 'list_notes', 'arguments': '{}'},
          ])
        else
          done([
            {
              'type': 'message',
              'content': [
                {'type': 'output_text', 'text': 'Henüz not yok.'},
              ],
            },
          ]),
      ]);
    });
    expect(await run(['chat', 'notlarım', 'neler?'], client: client), 0);
    expect('$out', contains('→ list_notes {}'));
    expect('$out', contains('←'));
    expect('$out', contains('Henüz not yok.'));
    expect('$out', contains(p.join('state', 'trace')));
    expect('$out', matches(RegExp(r'⏱ model \d+ ms')));
    expect('$out', matches(RegExp(r'⏱ tool list_notes \d+ ms')));
    expect(requests, ['/api/accounts/oauth/token', '/v1/models', '/v1/responses', '/v1/responses']);
    // The rotated refresh token is kept; no secret reaches the trace.
    final secrets = File(home('state/dev-secrets.json')).readAsStringSync();
    expect(secrets, contains('r2'));
    final log = trace();
    expect(log, contains('> POST https://api.openai.com/v1/responses'));
    expect(log, contains('notlarım neler?'));
    expect(log, contains('Henüz not yok.'));
    expect(log, contains('Authorization: ***'));
    for (final secret in ['a1', 'r1', 'r2']) {
      expect(log, isNot(contains('$secret"')), reason: secret);
      expect(log, isNot(contains('=$secret')), reason: secret);
    }
  });

  test('chat with a model given and an API-key provider from the environment', () async {
    final client = MockClient((_) async => http.Response('', 500));
    // No key: says which variable to set.
    expect(await run(['chat', '--provider=openai', 'hi'], client: client), 1);
    expect('$out', contains('NOTELORE_OPENAI_API_KEY'));
    final openai = MockClient(
      (request) async => events([
        done([
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': 'merhaba'},
            ],
          },
        ]),
      ]),
    );
    expect(
      await run(
        ['chat', '--provider=openai', 'hi'],
        client: openai,
        environment: {'NOTELORE_HOME': 'home', 'NOTELORE_OPENAI_API_KEY': 'sk-secret'},
      ),
      0,
    );
    expect('$out', contains('[openai · gpt-4o-mini]'));
    expect('$out', contains('merhaba'));
    expect(trace(), contains('Authorization: ***'));
    expect(trace(), isNot(contains('sk-secret')));
    // Claude goes through the traced transport; its key header is hidden too.
    final anthropic = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'content': [
            {'type': 'text', 'text': 'selam'},
          ],
          'stop_reason': 'end_turn',
        }),
        200,
      ),
    );
    expect(
      await run(
        ['chat', '--provider=anthropic', 'hi'],
        client: anthropic,
        environment: {'NOTELORE_HOME': 'home', 'NOTELORE_ANTHROPIC_API_KEY': 'sk-ant-secret'},
      ),
      0,
    );
    expect('$out', contains('selam'));
    expect(trace(), contains('x-api-key: ***'));
    expect(trace(), isNot(contains('sk-ant-secret')));
    // An unknown provider is an error, not a crash.
    expect(await run(['chat', '--provider=nope', 'hi']), 1);
  });

  test('eval: every case of a file against one model, with a report (#325)', () async {
    File(p.join(temp.path, 'cases.json')).writeAsStringSync(
      jsonEncode([
        {
          'id': 'greet',
          'kind': 'chat',
          'lang': 'en',
          'message': 'hi',
          'expect': {
            'answer': ['hello'],
          },
        },
        {
          'id': 'save',
          'kind': 'filing',
          'lang': 'en',
          'message': 'Remember: milk',
          'expect': {
            'tools': ['create_note'],
          },
        },
      ]),
    );
    final anthropic = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'content': [
            {'type': 'text', 'text': 'Hello there'},
          ],
          'stop_reason': 'end_turn',
        }),
        200,
      ),
    );
    expect(
      await run(
        ['eval', '--provider=anthropic', '--cases=cases.json'],
        client: anthropic,
        environment: {'NOTELORE_HOME': 'home', 'NOTELORE_ANTHROPIC_API_KEY': 'k'},
      ),
      0,
    );
    expect('$out', contains('[anthropic · claude-'));
    expect('$out', contains('ok   greet'));
    expect('$out', contains('FAIL save'));
    expect('$out', contains('chat: 1/1 (100%)'));
    expect('$out', contains('all: 1/2 (50%)'));
    // No cases file: said plainly.
    expect(await run(['eval', '--cases=missing.json']), 1);
    expect('$out', contains('missing.json'));

    // distill: only the passing turns, one JSON line each, for a fine-tune (#327).
    expect(
      await run(
        ['distill', '--provider=anthropic', '--cases=cases.json', '--out=train.jsonl'],
        client: anthropic,
        environment: {'NOTELORE_HOME': 'home', 'NOTELORE_ANTHROPIC_API_KEY': 'k'},
      ),
      0,
    );
    final lines = File(p.join(temp.path, 'train.jsonl')).readAsLinesSync();
    expect(lines, hasLength(1));
    expect(jsonDecode(lines.single), containsPair('tools', isNotEmpty));
    expect('$out', contains('kept 1 of 2'));
    expect(
      '$out',
      contains('excluded 0 passing turns (tool errors: 0; repeated calls: 0; counts may overlap)'),
    );

    // --slim: the prompt and tools of the model on the device (#447).
    expect(
      await run(
        ['distill', '--slim', '--provider=anthropic', '--cases=cases.json', '--out=slim.jsonl'],
        client: anthropic,
        environment: {'NOTELORE_HOME': 'home', 'NOTELORE_ANTHROPIC_API_KEY': 'k'},
      ),
      0,
    );
    final slim = jsonDecode(File(p.join(temp.path, 'slim.jsonl')).readAsLinesSync().single) as Map;
    expect(((slim['messages']! as List).first as Map)['content'], contains('Dictated sound-alike'));
  });

  test('distill keeps each turn as it goes, and a rerun goes on where it stopped (#327)', () async {
    File(p.join(temp.path, 'cases.json')).writeAsStringSync(
      jsonEncode([
        for (final id in ['one', 'two', 'three'])
          {
            'id': id,
            'kind': 'chat',
            'lang': 'en',
            'message': 'hi $id',
            'expect': <String, Object?>{},
          },
      ]),
    );
    var asked = 0;
    final anthropic = MockClient((_) async {
      asked++;
      return http.Response(
        jsonEncode({
          'content': [
            {'type': 'text', 'text': 'Hello'},
          ],
          'stop_reason': 'end_turn',
        }),
        200,
      );
    });
    final train = File(p.join(temp.path, 'train.jsonl'));
    final done = File(p.join(temp.path, 'train.jsonl.done'));
    Future<int> distill() => run(
      ['distill', '--provider=anthropic', '--cases=cases.json', '--out=train.jsonl'],
      client: anthropic,
      environment: {'NOTELORE_HOME': 'home', 'NOTELORE_ANTHROPIC_API_KEY': 'k'},
    );
    // A fresh run starts the file over, whatever was there.
    train.writeAsStringSync('stale\n');
    expect(await distill(), 0);
    expect(train.readAsLinesSync(), hasLength(3));
    expect(done.readAsLinesSync(), ['one\tkept', 'two\tkept', 'three\tkept']);
    // Stopped after "one" (the machine ran short of memory, say), and after
    // "two" was kept but before it was marked done: the rerun asks only for
    // the rest, keeps what "one" wrote and drops the half-finished line.
    train.writeAsStringSync('{"kept": "one"}\n{"kept": "two, half"}\n');
    done.writeAsStringSync('one\tkept\n');
    asked = 0;
    expect(await distill(), 0);
    expect(asked, 2);
    expect(train.readAsLinesSync(), hasLength(3));
    expect(train.readAsLinesSync().first, '{"kept": "one"}');
    expect(train.readAsStringSync(), isNot(contains('half')));
    expect(done.readAsLinesSync(), ['one\tkept', 'two\tkept', 'three\tkept']);
    expect('$out', contains('skipped 1 already done'));
    expect('$out', contains('kept 2 of 2'));
  });

  test('reprompt gives every example of a file the current prompt and tools', () async {
    final examples = [
      for (final prompt in ['old one', 'old two'])
        {
          'messages': [
            {'role': 'system', 'content': prompt},
            {'role': 'user', 'content': 'hi'},
          ],
          'tools': <Object?>[],
        },
    ];
    File(p.join(temp.path, 'mixed.jsonl'))
        .writeAsStringSync(examples.map((e) => '${jsonEncode(e)}\n').join());
    expect(await run(['reprompt', '--in=mixed.jsonl', '--out=same.jsonl']), 0);
    final lines = File(p.join(temp.path, 'same.jsonl')).readAsLinesSync();
    expect(lines, hasLength(2));
    for (final line in lines) {
      final example = jsonDecode(line) as Map;
      expect(((example['messages']! as List).first as Map)['content'], contains('Notelore'));
      expect(example['tools'], isNotEmpty);
    }
    expect(lines.toSet(), hasLength(1)); // the same prompt for both now
    expect('$out', contains('2 examples'));
  });

  test('distill excludes passing turns with tool errors or repeated calls', () async {
    File(p.join(temp.path, 'cases.json')).writeAsStringSync(
      jsonEncode([
        {
          'id': 'recovered',
          'kind': 'chat',
          'lang': 'en',
          'message': 'hi',
          'expect': {
            'answer': ['done'],
          },
        },
        {
          'id': 'repeated',
          'kind': 'chat',
          'lang': 'en',
          'message': 'again',
          'expect': {
            'answer': ['done'],
          },
        },
      ]),
    );
    var call = 0;
    final anthropic = MockClient((_) async {
      final step = call++;
      return http.Response(
        jsonEncode(switch (step) {
          0 || 2 || 3 => {
            'content': [
              {
                'type': 'tool_use',
                'id': 't$step',
                'name': 'list_notes',
                'input': step == 0 ? {'bad': true} : <String, Object?>{},
              },
            ],
            'stop_reason': 'tool_use',
          },
          _ => {
            'content': [
              {'type': 'text', 'text': 'done'},
            ],
            'stop_reason': 'end_turn',
          },
        }),
        200,
      );
    });
    expect(
      await run(
        ['distill', '--provider=anthropic', '--cases=cases.json', '--out=train.jsonl'],
        client: anthropic,
        environment: {'NOTELORE_HOME': 'home', 'NOTELORE_ANTHROPIC_API_KEY': 'k'},
      ),
      0,
    );
    expect('$out', contains('ok   recovered'));
    expect('$out', contains('ok   repeated'));
    // A read repeated with the same result is dropped from the example, not
    // the turn left out (a write repeated still is: eval_test).
    expect('$out', contains('kept 1 of 2'));
    expect(
      '$out',
      contains('excluded 1 passing turns (tool errors: 1; repeated calls: 0; counts may overlap)'),
    );
    final kept = File(p.join(temp.path, 'train.jsonl')).readAsLinesSync().single;
    // Once in the tool list, once as the call, once as its result: one call left.
    expect(RegExp('"list_notes"').allMatches(kept), hasLength(3));
  });

  test('a failing turn reports the error and where the trace is', () async {
    expect(await run(['chat', '--model=gpt=x', 'hi']), 1);
    expect('$out', contains('[chatgpt · gpt=x]')); // a value may hold '='
    expect('$out', contains('Error: not signed in with ChatGPT'));
    expect('$out', contains(p.join('state', 'trace')));
  });

  test('signin opens the browser; models lists the plan', () async {
    final opened = <Uri>[];
    final signin = runDev(
      ['signin'],
      environment: {'NOTELORE_HOME': 'home'},
      currentDirectory: temp,
      out: out,
      openBrowser: (url) async {
        opened.add(url);
        // Answer the loopback redirect with a refusal, as a browser would.
        final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
        unawaited(http.get(redirect.replace(queryParameters: {'error': 'access_denied'})));
      },
      client: MockClient((_) async => http.Response('', 500)),
    );
    expect(await signin, 1);
    expect(opened.first.host, 'auth.openai.com');
    expect('$out', contains('access_denied'));
    final granted = runDev(
      ['signin'],
      environment: {'NOTELORE_HOME': 'home'},
      currentDirectory: temp,
      out: out,
      openBrowser: (url) async {
        opened.add(url);
        final redirect = Uri.parse(url.queryParameters['redirect_uri']!);
        unawaited(
          http.get(
            redirect.replace(
              queryParameters: {
                'code': 'c',
                'state': url.queryParameters['state'],
                'client_id': 'oaiapp_9',
              },
            ),
          ),
        );
      },
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'access_token': 'a',
            'expires_in': 60,
            'refresh_token': 'r',
            'scope': 'openid chatgpt.tokens.use.direct',
          }),
          200,
        ),
      ),
    );
    expect(await granted, 0);
    expect('$out', contains('Signed in with ChatGPT.'));

    signedIn();
    final client = MockClient(
      (request) async => request.url.path.endsWith('/oauth/token')
          ? http.Response(
              jsonEncode({'access_token': 'a', 'expires_in': 60, 'refresh_token': 'r'}),
              200,
            )
          : http.Response(
              jsonEncode({
                'models': [
                  {'slug': 'gpt-a', 'visibility': 'list'},
                  {'slug': 'gpt-b', 'visibility': 'list'},
                ],
              }),
              200,
            ),
    );
    expect(await run(['models'], client: client), 0);
    expect('$out', contains('gpt-a\ngpt-b'));
  });

  test('the tracing client passes a stream through untouched and redacts forms', () async {
    final lines = <String>[];
    final traced = TracingClient(
      MockClient((request) async => http.Response('{"id_token": "secret-id", "ok": 1}', 200)),
      lines.add,
    );
    final response = await traced.post(
      Uri.parse('https://x.test/token'),
      headers: {'x-api-key': 'sk-ant', 'x-goog-api-key': 'AIza', 'Cookie': 'c=1'},
      body: {'code': 'c0de', 'code_verifier': 'v', 'grant_type': 'authorization_code'},
    );
    expect(response.body, '{"id_token": "secret-id", "ok": 1}');
    expect(lines.first, contains('code=***'));
    expect(lines.first, contains('code_verifier=***'));
    expect(lines.first, contains('grant_type=authorization_code'));
    for (final key in ['sk-ant', 'AIza', 'c=1']) {
      expect(lines.first, isNot(contains(key)));
    }
    expect(lines.last, contains('"id_token":"***"'));
    expect(lines.last, isNot(contains('secret-id')));
    traced.close();
  });
}
