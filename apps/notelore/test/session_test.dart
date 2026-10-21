import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/lock_state.dart';
import 'package:notelore/src/session.dart';
import 'package:notelore/src/strings.dart';
import 'package:notelore/src/theme.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

void main() {
  test('a fresh install is not ready', () async {
    final session = Harness().session();
    await session.load();
    expect(session.ready, isFalse);
    expect(session.spec, isNull);
  });

  test('connect validates, stores the key and builds the agent', () async {
    final harness = Harness();
    final session = harness.session();
    await session.connect(findProvider('anthropic'), ' sk-ant-1 ');
    expect(session.ready, isTrue);
    expect(session.spec!.name, 'anthropic');
    expect(session.model, 'claude-sonnet-5-5');
    expect(harness.created.single, ('anthropic', 'sk-ant-1', 'claude-sonnet-5-5'));
    expect(await const FlutterSecureStorage().read(key: 'notelore.anthropic.api_key'), 'sk-ant-1');
    final settings = File(p.join(harness.paths.state.path, 'settings.json')).readAsStringSync();
    expect(settings, contains('"provider":"anthropic"'));
  });

  test('a rejected key changes nothing', () async {
    final harness = Harness(rejected: const KeyValidationError('Anthropic rejected the key'));
    final session = harness.session();
    await expectLater(
      session.connect(findProvider('anthropic'), 'bad'),
      throwsA(isA<KeyValidationError>()),
    );
    expect(session.ready, isFalse);
    expect(await const FlutterSecureStorage().read(key: 'notelore.anthropic.api_key'), isNull);
  });

  test('settings that cannot be saved leave no key behind', () async {
    final harness = Harness();
    // A folder where settings.json goes: writing the settings fails.
    Directory(p.join(harness.paths.state.path, 'settings.json', 'blocker'))
        .createSync(recursive: true);
    final session = harness.session();
    await expectLater(
      session.connect(findProvider('anthropic'), 'sk-ant-1'),
      throwsA(isA<FileSystemException>()),
    );
    expect(session.ready, isFalse);
    expect(session.spec, isNull);
    expect(await const FlutterSecureStorage().read(key: 'notelore.anthropic.api_key'), isNull);
  });

  test('a failed reconnect puts the previous key back', () async {
    final harness = Harness();
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'old-key');
    final settings = File(p.join(harness.paths.state.path, 'settings.json'));
    final saved = settings.readAsStringSync();
    settings.deleteSync();
    Directory(p.join(settings.path, 'blocker')).createSync(recursive: true);
    await expectLater(
      session.connect(findProvider('anthropic'), 'new-key'),
      throwsA(isA<FileSystemException>()),
    );
    expect(await const FlutterSecureStorage().read(key: 'notelore.anthropic.api_key'), 'old-key');
    expect(session.ready, isTrue); // still on the old key
    Directory(settings.path).deleteSync(recursive: true);
    settings.writeAsStringSync(saved);
    final again = harness.session();
    await again.load();
    expect(harness.created.last, ('anthropic', 'old-key', 'claude-sonnet-5-5'));
  });

  test('a keystore that fails too does not hide the settings error', () async {
    final harness = Harness();
    final session = Session(
      harness.paths,
      keys: const _BrokenDelete(),
      validate: (spec, key) async => <String>[],
      makeProvider: (spec, key, {model, planToken, webSearch = false}) => harness.provider,
    );
    addTearDown(session.dispose);
    Directory(p.join(harness.paths.state.path, 'settings.json', 'blocker'))
        .createSync(recursive: true);
    await expectLater(
      session.connect(findProvider('anthropic'), 'k'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('a model that cannot be saved is not switched to', () async {
    final harness = Harness();
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    final settings = File(p.join(harness.paths.state.path, 'settings.json'))..deleteSync();
    Directory(p.join(settings.path, 'blocker')).createSync(recursive: true);
    await expectLater(session.setModel('claude-x'), throwsA(isA<FileSystemException>()));
    expect(session.model, 'claude-sonnet-5-5');
  });

  test('connecting keeps the models the key can use, across a restart', () async {
    final harness = Harness()..models = ['claude-opus-5-5', 'claude-sonnet-5-5'];
    final session = harness.session();
    expect(session.models, isEmpty);
    await session.connect(findProvider('anthropic'), 'k');
    expect(session.models, ['claude-opus-5-5', 'claude-sonnet-5-5']);
    final again = harness.session();
    await again.load();
    expect(again.models, ['claude-opus-5-5', 'claude-sonnet-5-5']); // no network needed
    await again.setModel('claude-opus-5-5');
    final third = harness.session();
    await third.load();
    expect(third.models, hasLength(2)); // choosing a model keeps the list
  });

  test('the model list can be refreshed; a failed refresh keeps the old one', () async {
    final harness = Harness();
    final session = harness.session();
    await session.refreshModels(); // nothing connected: nothing to do
    await session.connect(findProvider('anthropic'), 'k');
    harness.models = ['newer'];
    await session.refreshModels();
    expect(session.models, ['newer']);
    final again = harness.session();
    await again.load();
    expect(again.models, ['newer']);
  });

  test('a refresh with the key gone from the keystore sends back to setup', () async {
    final session = Harness().session();
    await session.connect(findProvider('anthropic'), 'k');
    await const FlutterSecureStorage().delete(key: 'notelore.anthropic.api_key');
    await session.refreshModels();
    expect(session.ready, isFalse);
  });

  test('logging out while a refresh is in flight drops the late list', () async {
    final harness = Harness();
    final answer = Completer<List<String>>();
    var calls = 0;
    final session = Session(
      harness.paths,
      validate: (spec, key) => calls++ == 0 ? Future.value(['a']) : answer.future,
      makeProvider: (spec, key, {model, planToken, webSearch = false}) => harness.provider,
    );
    addTearDown(session.dispose);
    await session.connect(findProvider('anthropic'), 'k');
    final refresh = session.refreshModels();
    await session.logout();
    answer.complete(['late']);
    await refresh; // no null-check crash
    expect(session.models, isEmpty);
    expect(File(p.join(harness.paths.state.path, 'settings.json')).existsSync(), isFalse);
  });

  test('a refresh the provider refuses changes nothing', () async {
    final harness = Harness(rejected: const TransientValidationError('offline'));
    final session = harness.session();
    File(p.join(harness.paths.state.path, 'settings.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{"provider": "ollama", "model": "m", "models": ["m"]}');
    await session.load();
    await expectLater(session.refreshModels(), throwsA(isA<TransientValidationError>()));
    expect(session.models, ['m']);
  });

  test('settings from before the model list load, then the list fills in', () async {
    final harness = Harness();
    File(p.join(harness.paths.state.path, 'settings.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{"provider": "ollama", "model": "m"}');
    final session = harness.session();
    await session.load();
    expect(session.ready, isTrue);
    await pumpEventQueue(); // the start refresh
    expect(session.models, harness.models);
    expect(session.model, 'm');
  });

  test('settings and key survive a restart', () async {
    final harness = Harness();
    await harness.session().connect(findProvider('openai'), 'sk-1', model: 'gpt-x');
    final again = harness.session();
    await again.load();
    expect(again.ready, isTrue);
    expect((again.spec!.name, again.model), ('openai', 'gpt-x'));
    expect(harness.created.last, ('openai', 'sk-1', 'gpt-x'));
  });

  test('a saved provider whose key is gone is not ready', () async {
    final harness = Harness();
    await harness.session().connect(findProvider('gemini'), 'gk');
    await const FlutterSecureStorage().delete(key: 'notelore.gemini.api_key');
    final again = harness.session();
    await again.load();
    expect(again.ready, isFalse);
  });

  test('damaged settings start over', () async {
    final harness = Harness();
    File(p.join(harness.paths.state.path, 'settings.json'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{not json');
    final session = harness.session();
    await session.load();
    expect(session.ready, isFalse);
    File(p.join(harness.paths.state.path, 'settings.json'))
        .writeAsStringSync('{"provider": "bard"}');
    await session.load();
    expect(session.ready, isFalse);
  });

  test('Ollama needs no key, and starts on a model it has (#471)', () async {
    final harness = Harness()..models = ['llama3.2:3b', 'notelore-qwen3-4b-v3:latest'];
    await harness.session().connect(findProvider('ollama'), '');
    final again = harness.session();
    await again.load();
    expect(again.ready, isTrue);
    expect(harness.created.last, ('ollama', '', 'notelore-qwen3-4b-v3:latest'));
    // None installed: says so, never a model Ollama does not have.
    harness.models = [];
    await expectLater(
      harness.session().connect(findProvider('ollama'), ''),
      throwsA(isA<NoLocalModel>()),
    );
  });

  test('notes archived since the last turn are named to the model as unusable (#205)', () async {
    final harness = Harness(answers: ['Okudum.', 'Tamam.', 'Peki.']);
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    createNote(harness.paths.notes.path, 'project', 'Mopsos', today: today);
    await session.send('kitaplarım ne');
    expect(harness.provider.asked.last, 'kitaplarım ne'); // nothing changed yet
    // Deleted here (or archived on another device and synced): gone from the notes.
    await session.deleteNote(session.listNotes().firstWhere((n) => n.title == 'Kitaplar'));
    await session.send('peki şimdi');
    expect(harness.provider.asked.last, allOf(contains('peki şimdi'), contains('Kitaplar')));
    expect(harness.provider.asked.last, contains('archive'));
    expect(session.transcript[2].text, 'peki şimdi'); // the user's words, as typed
    await session.send('ve sonra');
    expect(harness.provider.asked.last, 've sonra'); // said once
  });

  test('a turn that failed keeps the archive notice for the next one (#205)', () async {
    final harness = Harness(answers: ['Okudum.', const HttpError(500, 'offline'), 'Tamam.']);
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    await session.send('kitaplarım ne');
    await session.deleteNote(session.listNotes().single);
    await session.send('peki'); // fails: the model never answered it
    await session.send('şimdi');
    expect(harness.provider.asked.last, allOf(contains('şimdi'), contains('Kitaplar')));
  });

  /// Until the queue has run, or nothing more can go out.
  Future<void> settled(Session session) async {
    for (var i = 0; i < 50; i++) {
      await pumpEventQueue();
      if (!session.busy) return;
    }
  }

  test(
    'offline: a message waits, survives a restart and goes out once when it can (#214)',
    () async {
      final harness = Harness(answers: [const NetworkError('offline'), 'Kaydettim.']);
      final session = harness.session();
      await session.connect(findProvider('anthropic'), 'k');
      await session.send('kitabı kaydet');
      expect(session.transcript.map((l) => (l.role, l.text)), [
        (ChatRole.pending, 'kitabı kaydet'),
      ]);
      expect(session.lastSent, isNull); // nothing to resend: it is still on its way

      // The app is closed and opened again: the message is still there, and goes out.
      final again = harness.session();
      await again.load();
      await settled(again);
      expect(harness.provider.asked, ['kitabı kaydet', 'kitabı kaydet']);
      expect(again.transcript.map((l) => (l.role, l.text)), [
        (ChatRole.user, 'kitabı kaydet'),
        (ChatRole.assistant, 'Kaydettim.'),
      ]);
      final third = harness.session();
      await third.load();
      expect(third.transcript, isEmpty); // gone once it went out
    },
  );

  test('a usage limit waits too, and later messages keep their order (#214)', () async {
    const limit = HttpError(429, 'usage limit reached');
    final harness = Harness(answers: [limit, limit, 'Bir.', 'İki.']);
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    await session.send('bir');
    // A new message tries what waits first (still over the limit), then waits behind it.
    await session.send('iki');
    await settled(session);
    expect(harness.provider.asked, ['bir', 'bir']);
    expect(session.transcript.map((l) => l.role), [ChatRole.pending, ChatRole.pending]);
    await session.retryNow();
    await settled(session);
    expect(harness.provider.asked, ['bir', 'bir', 'bir', 'iki']);
    // Both were written before either answer, so they stay first.
    expect(session.transcript.map((l) => (l.role, l.text)), [
      (ChatRole.user, 'bir'),
      (ChatRole.user, 'iki'),
      (ChatRole.assistant, 'Bir.'),
      (ChatRole.assistant, 'İki.'),
    ]);
    await session.retryNow(); // nothing waiting: nothing happens
    expect(harness.provider.asked, hasLength(4));
  });

  test('it tries again by itself: on return to the app and every little while', () async {
    final harness = Harness(
      answers: [const NetworkError('offline'), const NetworkError('offline'), 'Geldi.'],
    );
    // The timer ticks when the test says: no real time to race on a busy machine (#524).
    Duration? every;
    void Function()? tick;
    final session = harness.session(
      every: (period, onTick) {
        every = period;
        tick = () => onTick(_Ticker());
        return _Ticker();
      },
    );
    await session.connect(findProvider('anthropic'), 'k');
    session.setForeground(false); // the phone put Notelore away mid-reply
    await session.send('selam');
    session.setForeground(true); // back: tried again, still offline
    await settled(session);
    expect(harness.provider.asked, ['selam', 'selam']);
    expect(every, const Duration(hours: 1)); // the harness's; the app's is a minute
    tick!(); // the timer tries once more
    await settled(session);
    expect(session.transcript.last.text, 'Geldi.');
    expect(harness.provider.asked, ['selam', 'selam', 'selam']);
  });

  test(
    'a waiting message that then fails for another reason is an error and waits no more',
    () async {
      final harness = Harness(
        answers: [const NetworkError('offline'), const HttpError(500, 'down')],
      );
      final session = harness.session();
      await session.connect(findProvider('anthropic'), 'k');
      // A folder where the queue's file goes: it cannot be kept, but it still waits.
      Directory(p.join(harness.paths.state.path, 'pending.json')).createSync(recursive: true);
      await session.send('selam');
      expect(session.transcript.single.role, ChatRole.pending);
      await session.retryNow();
      await settled(session);
      expect(session.transcript.map((l) => l.role), [ChatRole.user, ChatRole.error]);
      await session.retryNow();
      expect(harness.provider.asked, hasLength(2)); // not tried again
    },
  );

  test('written while a waiting message is retried: it waits behind it, kept too', () async {
    final retry = Completer<AgentResponse>();
    const offline = NetworkError('offline');
    final harness = Harness(answers: [offline, retry.future, offline]); // the last: after a restart
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    await session.send('bir');
    final retrying = session.retryNow(); // in flight
    await pumpEventQueue();
    await session.send('iki'); // while it runs
    retry.completeError(const NetworkError('offline')); // still offline
    await retrying;
    await settled(session);
    expect(session.transcript.map((l) => (l.role, l.text)), [
      (ChatRole.pending, 'bir'),
      (ChatRole.pending, 'iki'),
    ]);
    final again = harness.session();
    await again.load();
    expect(again.transcript.map((l) => l.text), ['bir', 'iki']); // both kept
  });

  test('a message that joined a turn which then has to wait is kept in the queue too', () async {
    final first = Completer<AgentResponse>();
    const offline = NetworkError('offline');
    final harness = Harness(answers: [first.future, offline]); // the last: after a restart
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    final sending = session.send('bir');
    await pumpEventQueue();
    await session.send('iki'); // joins the running turn
    first.completeError(offline);
    await sending;
    expect(session.transcript.map((l) => (l.role, l.text)), [
      (ChatRole.pending, 'bir'),
      (ChatRole.pending, 'iki'),
    ]);
    final again = harness.session();
    await again.load();
    expect(again.transcript.map((l) => l.text), ['bir', 'iki']); // both kept
  });

  test('logging out while a waiting message is retried leaves nothing stuck', () async {
    final retry = Completer<AgentResponse>();
    final harness = Harness(answers: [const NetworkError('offline'), retry.future]);
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    await session.send('bir');
    final retrying = session.retryNow();
    await pumpEventQueue();
    await session.logout();
    retry.complete(
      const AgentResponse([
        {'type': 'text', 'text': 'Geldi.'},
      ], 'end_turn'),
    );
    await retrying;
    expect(session.busy, isFalse);
  });

  test('a turn that wrote notes and then failed is an error, never queued', () async {
    final harness = Harness(
      answers: [
        const AgentResponse([
          {
            'type': 'tool_use',
            'id': 't1',
            'name': 'create_note',
            'input': {'kind': 'topic', 'title': 'Kitaplar'},
          },
          {
            'type': 'tool_use',
            'id': 't2',
            'name': 'add_note_entry',
            'input': {'slug': 'kitaplar', 'text': 'Dune.'},
          },
        ], 'tool_use'),
        const NetworkError('offline'),
      ],
    );
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    await session.send('iki');
    expect(session.transcript.last.role, ChatRole.error);
    expect(session.transcript.last.text, contains(session.strings.notesMayBeSaved));
    await session.retryNow();
    expect(harness.provider.asked, hasLength(2)); // not sent again
  });

  test('logging out drops what waits, like the rest of the conversation', () async {
    final harness = Harness(answers: [const NetworkError('offline'), 'Geldi.']);
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    await session.send('kitabı kaydet');
    await session.logout();
    final again = harness.session();
    await again.load();
    expect(again.transcript, isEmpty);
    expect(harness.provider.asked, ['kitabı kaydet']);
  });

  group('images (#278)', () {
    final png = imageBlock('image/png', [1, 2, 3]);
    const message = 'what is it\n\n<attached image="r.png"/>';

    test('go to the model with the message; the transcript keeps only their name', () async {
      final harness = Harness(answers: ['A receipt.', 'Again.', 'Words.']);
      final session = harness.session();
      await session.connect(findProvider('anthropic'), 'k');
      expect(session.acceptsImages, isTrue);
      await session.send(message, images: [png]);
      expect(harness.provider.asked.single, allOf(contains('image/png'), contains('AQID')));
      expect(session.transcript.first, (role: ChatRole.user, text: message));
      // Resend sends the picture again, too.
      await session.resend();
      expect(harness.provider.asked.last, contains('AQID'));
      // Switched to a provider that cannot look at images: the words only.
      await session.connect(findProvider('ollama'), '');
      await session.resend();
      expect(harness.provider.asked.last, allOf(contains('what is it'), isNot(contains('AQID'))));
    });

    test('never wait offline: an error says to send them again; nothing is kept', () async {
      final harness = Harness(answers: [const NetworkError('offline')]);
      final session = harness.session();
      await session.connect(findProvider('anthropic'), 'k');
      await session.send(message, images: [png]);
      expect(session.transcript.map((l) => l.role), [ChatRole.user, ChatRole.error]);
      expect(session.transcript.last.text, contains('Images cannot wait'));
      expect(File(p.join(harness.paths.state.path, 'pending.json')).existsSync(), isFalse);
      final again = harness.session();
      await again.load();
      expect(again.transcript, isEmpty);
    });

    test('Ollama is not sent any', () async {
      final session = Harness().session();
      await session.connect(findProvider('ollama'), '');
      expect(session.acceptsImages, isFalse);
    });

    test('DeepSeek takes them only on its vision model', () async {
      final harness = Harness()..models = ['deepseek-flash', 'deepseek-v4-pro'];
      final session = harness.session();
      await session.connect(findProvider('deepseek'), 'sk-d');
      expect(session.acceptsImages, isTrue);
      await session.setModel('deepseek-v4-pro');
      expect(session.acceptsImages, isFalse);
    });
  });

  test('send runs the agent and keeps the transcript', () async {
    final harness = Harness(answers: ['Merhaba!']);
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    var notified = 0;
    session.addListener(() => notified++);
    await session.send('  selam ');
    expect(harness.provider.asked, ['selam']);
    expect(session.transcript.map((l) => (l.role, l.text)), [
      (ChatRole.user, 'selam'),
      (ChatRole.assistant, 'Merhaba!'),
    ]);
    expect(session.busy, isFalse);
    expect(notified, greaterThanOrEqualTo(2));
    await session.send('   '); // blank: nothing happens
    expect(session.transcript, hasLength(2));
  });

  test('timing (#232): the wait in the queue, each model and tool call; no text', () async {
    final harness = Harness(answers: ['Merhaba!']);
    final timings = <String>[];
    final session = harness.session(timing: timings.add);
    await session.connect(findProvider('anthropic'), 'k');
    await session.send('gizli');
    expect(timings, hasLength(2));
    expect(timings[0], matches(RegExp(r'^queue \d+ ms$')));
    expect(timings[1], matches(RegExp(r'^model \d+ ms$')));
  });

  test('written while it works: taken into the running turn, one answer', () async {
    final first = Completer<AgentResponse>();
    final harness = Harness(answers: [first.future, 'İkisini de yanıtladım.']);
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    final turn = session.send('ne okuyorum?');
    await Future<void>.delayed(Duration.zero);
    await session.send('yazarı da kim?'); // the model is still working
    expect(session.transcript.last.text, 'yazarı da kim?');
    first.complete(
      const AgentResponse([
        {'type': 'tool_use', 'id': 't1', 'name': 'list_notes', 'input': <String, Object?>{}},
      ], 'tool_use'),
    );
    await turn;
    await pumpEventQueue();
    expect(harness.provider.asked.last, contains('yazarı da kim?'));
    expect(session.transcript.map((l) => l.text), [
      'ne okuyorum?',
      'yazarı da kim?',
      'İkisini de yanıtladım.',
    ]);
  });

  test('written while it works, but the turn ends first: sent together right after', () async {
    final first = Completer<AgentResponse>();
    final harness = Harness(answers: [first.future, 'İki ve üç.']);
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    final turn = session.send('bir');
    await Future<void>.delayed(Duration.zero);
    await session.send('iki');
    await session.send('üç');
    first.complete(
      const AgentResponse([
        {'type': 'text', 'text': 'Bir.'},
      ], 'end_turn'),
    );
    await turn;
    await pumpEventQueue();
    expect(harness.provider.asked.last, 'iki\n\nüç'); // one follow-up turn
    expect(session.transcript.map((l) => l.text), ['bir', 'iki', 'üç', 'Bir.', 'İki ve üç.']);
    expect(session.busy, isFalse);
  });

  test('a turn that fails after taking a message: that message still goes out', () async {
    final first = Completer<AgentResponse>();
    final harness = Harness(
      answers: [first.future, const HttpError(500, 'offline'), 'Yazarı Can Dündar.'],
    );
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    var busyFlips = 0;
    var wasBusy = true;
    session.addListener(() {
      if (session.busy != wasBusy) busyFlips++;
      wasBusy = session.busy;
    });
    final turn = session.send('ne okuyorum?');
    await Future<void>.delayed(Duration.zero);
    await session.send('yazarı kim?');
    first.complete(
      const AgentResponse([
        {'type': 'tool_use', 'id': 't1', 'name': 'list_notes', 'input': <String, Object?>{}},
      ], 'tool_use'), // the turn takes "yazarı kim?" here, then fails
    );
    await turn;
    expect(harness.provider.asked.last, 'yazarı kim?'); // sent again, on its own
    expect(session.transcript.map((l) => l.role), [
      ChatRole.user,
      ChatRole.user,
      ChatRole.error,
      ChatRole.assistant,
    ]);
    expect(busyFlips, 1); // busy the whole time, off once at the end
  });

  test('a running turn can be stopped', () async {
    final harness = Harness(answers: [Completer<AgentResponse>().future]);
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    session.stop(); // nothing running: nothing happens
    final turn = session.send('selam');
    await Future<void>.delayed(Duration.zero);
    expect(session.busy, isTrue);
    session.stop();
    await turn;
    expect(session.transcript.last.role, ChatRole.error);
    expect(session.transcript.last.text, 'Stopped.');
    expect(session.busy, isFalse);
    // Stopped while still queued (e.g. behind a sync): the model is never asked.
    final queued = session.send('again');
    session.stop();
    await queued;
    expect(harness.provider.asked, ['selam']);
    expect(session.transcript.last.text, 'Stopped.');
  });

  test('a failed turn shows an error line and the next one works', () async {
    final harness = Harness(answers: [const HttpError(500, 'offline'), 'back']);
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    await session.send('one');
    expect(session.transcript.last.role, ChatRole.error);
    expect(session.transcript.last.text, contains('having trouble')); // kindly, not raw (#306)
    await session.send('two');
    expect(session.transcript.last.text, 'back');
  });

  test('resend sends the last message again, exactly, also after a failure', () async {
    final harness = Harness(answers: [const HttpError(500, 'offline'), 'back']);
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    expect(session.lastSent, isNull);
    await session.resend(); // nothing sent yet: nothing happens
    expect(harness.provider.asked, isEmpty);
    await session.send('  one  ');
    expect(session.lastSent, 'one');
    expect(session.transcript.last.role, ChatRole.error);
    expect(session.transcript.last.text, isNot(contains(session.strings.notesMayBeSaved)));
    await session.resend();
    expect(harness.provider.asked, ['one', 'one']); // once per resend
    expect(session.transcript.map((l) => l.role), [
      ChatRole.user,
      ChatRole.error,
      ChatRole.user, // the resend shows as a message of its own
      ChatRole.assistant,
    ]);
    expect(session.transcript[2].text, 'one');
    expect(session.transcript.last.text, 'back');
  });

  test('a failure after a note was written warns before a resend', () async {
    final harness = Harness(
      answers: [
        const AgentResponse([
          {
            'type': 'tool_use',
            'id': 't1',
            'name': 'create_note',
            'input': {'kind': 'project', 'title': 'Mopsos'},
          },
          {
            'type': 'tool_use',
            'id': 't2',
            'name': 'add_note_entry',
            'input': {'slug': 'mopsos', 'text': 'Started.'},
          },
        ], 'tool_use'),
        const NetworkError('offline'), // the note is written, the answer fails
      ],
    );
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    await session.send('note Mopsos');
    expect(session.transcript.last.role, ChatRole.error);
    expect(session.transcript.last.text, contains(session.strings.errorOffline));
    expect(session.transcript.last.text, contains(session.strings.notesMayBeSaved));
  });

  test('the agent really writes notes, and the notes list sees them', () async {
    final harness = Harness(
      answers: [
        const AgentResponse([
          {
            'type': 'tool_use',
            'id': 't1',
            'name': 'create_note',
            'input': {'kind': 'project', 'title': 'Mopsos'},
          },
        ], 'tool_use'),
        'Created.',
      ],
    );
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    await session.send('Mopsos diye proje aç');
    final notes = session.listNotes();
    expect(notes.map((n) => n.title), ['Mopsos']);
    expect(session.readNote(notes.single), contains('\n# Mopsos\n'));
  });

  test('setModel rebuilds the agent with the new model', () async {
    final harness = Harness();
    final session = harness.session();
    await session.setModel('ignored before connecting');
    await session.connect(findProvider('anthropic'), 'k');
    await session.setModel(' claude-x ');
    expect(session.model, 'claude-x');
    expect(harness.created.last, ('anthropic', 'k', 'claude-x'));
    await session.setModel('');
    expect(session.model, 'claude-sonnet-5-5'); // blank goes back to the default
    // Ollama: a blank goes back to an installed model, never a fixed name (#471).
    harness.models = ['llama3.2:3b', 'qwen3:4b-instruct'];
    await session.connect(findProvider('ollama'), '');
    await session.setModel('');
    expect(session.model, 'qwen3:4b-instruct');
  });

  test('an API key starts on the cheapest model it lists', () async {
    final harness = Harness()..models = ['gpt-5', 'gpt-5-nano', 'gpt-5-mini'];
    final session = harness.session();
    await session.connect(findProvider('openai'), 'sk');
    expect(session.model, 'gpt-5-nano');
    harness.models = [];
    await session.connect(findProvider('openai'), 'sk');
    expect(session.model, 'gpt-4o-mini'); // nothing listed: the fixed default
  });

  test('Gemini starts on its free-tier model, not the cheapest preview (#400)', () async {
    // A free AI Studio key lists previews and lite models whose free quota is 0.
    final harness = Harness()
      ..models = [
        'gemini-2.5-flash-lite',
        'gemini-3-flash-preview',
        'gemini-2.5-flash',
        'gemma-3-4b-it',
        'gemini-2.5-pro',
      ];
    final session = harness.session();
    await session.connect(findProvider('gemini'), 'AIza');
    expect(session.model, 'gemini-2.5-flash');
    expect(session.defaultModel, 'gemini-2.5-flash');
    harness.models = ['gemini-2.5-flash-lite', 'gemini-2.5-pro']; // no flash listed: cheapest
    await session.connect(findProvider('gemini'), 'AIza');
    expect(session.model, 'gemini-2.5-flash-lite');
  });

  test('every start refreshes the model list and keeps the chosen model', () async {
    final harness = Harness();
    final first = harness.session();
    await first.connect(findProvider('anthropic'), 'k');
    await first.setModel('model-b');
    harness.models = ['model-new', 'model-b'];
    final again = harness.session();
    await again.load();
    await pumpEventQueue(); // the refresh runs in the background
    expect(again.models, ['model-new', 'model-b']);
    expect(again.model, 'model-b');
    // Even when the provider no longer lists it, the chosen model stays.
    harness.models = ['model-new'];
    final third = harness.session();
    expect(third.modelGone, isFalse); // nothing connected yet
    await third.load();
    await pumpEventQueue();
    expect(third.model, 'model-b');
    expect(third.modelGone, isTrue); // the chat asks the user to pick another
    await third.setModel('model-new');
    expect(third.modelGone, isFalse);
    // Offline or refused: the old list stays, and nothing is thrown.
    harness.rejected = const TransientValidationError('offline');
    final offline = harness.session();
    await offline.load();
    await pumpEventQueue();
    expect(offline.models, ['model-new']);
    expect(offline.ready, isTrue);
  });

  test('the app language: the device one first, then the one picked, remembered', () async {
    final harness = Harness();
    final turkishPhone = harness.session(systemLanguage: 'tr');
    await turkishPhone.load();
    expect(turkishPhone.language, AppLanguage.system);
    expect(turkishPhone.strings.languageCode, 'tr');
    turkishPhone.setLanguage(AppLanguage.en);
    expect(turkishPhone.strings.chat, 'Chat');
    final again = harness.session(systemLanguage: 'tr');
    await again.load();
    expect(again.language, AppLanguage.en);
    // A damaged or unknown saved value: back to the device language.
    File(p.join(harness.paths.state.path, 'ui.json')).writeAsStringSync('{"language": "xx"}');
    final unknown = harness.session(systemLanguage: 'tr');
    await unknown.load();
    expect(unknown.language, AppLanguage.system);
    File(p.join(harness.paths.state.path, 'ui.json')).writeAsStringSync('{not json');
    final damaged = harness.session();
    await damaged.load();
    expect(damaged.language, AppLanguage.system);
    // A file that cannot be written: the choice still applies, just not remembered.
    File(p.join(harness.paths.state.path, 'ui.json')).deleteSync();
    Directory(p.join(harness.paths.state.path, 'ui.json')).createSync();
    // The time of the change cannot be kept either: still no error.
    File(p.join(harness.paths.state.path, 'settings-changed.txt')).deleteSync();
    Directory(p.join(harness.paths.state.path, 'settings-changed.txt')).createSync();
    damaged.setLanguage(AppLanguage.tr);
    expect(damaged.strings.languageCode, 'tr');
  });

  test('the theme and the appearance: picked, remembered, lagoon and system by default', () async {
    final harness = Harness();
    final first = harness.session();
    await first.load();
    expect(first.palette, Palette.lagoon);
    expect(first.appearance, Appearance.system);
    first
      ..setPalette(Palette.forest)
      ..setAppearance(Appearance.dark)
      ..setLanguage(AppLanguage.tr);
    final again = harness.session();
    await again.load();
    expect(
      (again.palette, again.appearance, again.language),
      (Palette.forest, Appearance.dark, AppLanguage.tr),
    );
  });

  test('web search: on by default where the provider has it, and can be turned off', () async {
    final harness = Harness();
    final session = harness.session();
    await session.load();
    expect(session.webSearch, isTrue);
    await session.connect(findProvider('anthropic'), 'k');
    expect(harness.searches.last, isTrue);
    await session.setWebSearch(false);
    expect(harness.searches.last, isFalse); // the provider is rebuilt without it
    final again = harness.session();
    await again.load();
    expect(again.webSearch, isFalse);
    // Gemini cannot search alongside the note tools: never asked to.
    await again.setWebSearch(true);
    await again.connect(findProvider('gemini'), 'g');
    expect(harness.searches.last, isFalse);
  });

  test('in Turkish, the sync summary and a stopped turn read in Turkish', () async {
    final harness = Harness(answers: [Completer<AgentResponse>().future]);
    final session = harness.session(systemLanguage: 'tr');
    await session.connect(findProvider('anthropic'), 'k');
    final turn = session.send('selam');
    await Future<void>.delayed(Duration.zero);
    session.stop();
    await turn;
    expect(session.transcript.last.text, 'Durduruldu.');
  });

  test('switching the model keeps the conversation', () async {
    final harness = Harness(answers: ['first', 'second']);
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    await session.send('a');
    await session.setModel('model-b');
    await session.send('b');
    // The second turn, on the new model, still carries the first one.
    expect(harness.provider.lengths, [1, 3]);
    expect(harness.created.last, ('anthropic', 'k', 'model-b'));
  });

  test('the app lock: off at first; with a PIN the next start asks for it', () async {
    final harness = Harness();
    final session = harness.session();
    await session.load();
    expect(session.lock.enabled, isFalse);
    expect(session.lock.locked, isFalse);
    await session.lock.set('2468');
    expect(session.lock.enabled, isTrue);
    expect(session.lock.locked, isFalse); // whoever just set it is in
    // In the keystore as a salted hash only; nowhere in the notes or state folders.
    final stored = await const FlutterSecureStorage().read(key: 'notelore.lock');
    expect(stored, allOf(isNotNull, isNot(contains('2468'))));
    for (final dir in [harness.paths.notes, harness.paths.state]) {
      if (!dir.existsSync()) continue;
      for (final file in dir.listSync(recursive: true).whereType<File>()) {
        expect(file.readAsBytesSync().toString(), isNot(contains(utf8.encode('2468').toString())));
      }
    }
    final again = harness.session();
    await again.load();
    expect(again.lock.enabled, isTrue);
    expect(again.lock.locked, isTrue);
    expect(await again.lock.unlock('1357'), isFalse);
    expect(again.lock.locked, isTrue);
    expect(await again.lock.unlock('2468'), isTrue);
    expect(again.lock.locked, isFalse);
  });

  test('the real app hashes the lock in another isolate, and it still checks out', () async {
    final harness = Harness();
    final session = Session(harness.paths, lockIterations: 10); // the default offThread
    addTearDown(session.dispose);
    await session.lock.set('2468');
    final again = Session(harness.paths, lockIterations: 10);
    addTearDown(again.dispose);
    expect(await again.lock.unlock('1357'), isFalse); // load() is left out: it would go online
    expect(await again.lock.unlock('2468'), isTrue);
  });

  test('a minute or more in the background locks again; a shorter trip does not', () async {
    var now = DateTime.utc(2026, 10, 17, 12);
    final session = Harness().session(clock: () => now);
    await session.lock.set('2468');
    session.lock.backgrounded();
    now = now.add(const Duration(seconds: 59)); // a quick look at another app
    session.lock.foregrounded();
    expect(session.lock.locked, isFalse);
    session.lock.backgrounded(); // hidden...
    now = now.add(const Duration(seconds: 40));
    session.lock.backgrounded(); // ...then paused: the trip started at the first
    now = now.add(const Duration(seconds: 20));
    session.lock.foregrounded();
    expect(session.lock.locked, isTrue);
    expect(await session.lock.unlock('2468'), isTrue);
    session.lock.foregrounded(); // back without having been away: nothing
    expect(session.lock.locked, isFalse);
    // Without a lock, nothing locks.
    expect(await session.lock.remove('2468'), isTrue);
    session.lock.backgrounded();
    now = now.add(const Duration(minutes: 5));
    session.lock.foregrounded();
    expect(session.lock.locked, isFalse);
  });

  test(
    'the device lock: on after the device says yes; it opens the app; no secret kept (#295)',
    () async {
      final harness = Harness();
      final session = harness.session();
      expect(await session.lock.deviceAvailable(), isTrue);
      harness.deviceAuth.answers.add(false); // a cancel turns nothing on
      expect(await session.lock.useDevice('turn on'), isFalse);
      expect(session.lock.enabled, isFalse);
      harness.deviceAuth.answers.add(true);
      expect(await session.lock.useDevice('turn on'), isTrue);
      expect(session.lock.kind, LockKind.device);
      expect(session.lock.locked, isFalse); // whoever just set it is in
      // The keystore holds a marker, never a secret.
      expect(await const FlutterSecureStorage().read(key: 'notelore.lock'), 'device');

      final again = harness.session();
      await again.lock.load();
      expect(again.lock.locked, isTrue);
      expect(again.lock.kind, LockKind.device);
      expect(await again.lock.unlock('2468'), isFalse); // no text opens a device lock
      for (var i = 0; i < 8; i++) {
        harness.deviceAuth.answers.add(false);
        expect(await again.lock.unlockWithDevice('open'), isFalse);
      }
      // The device counts its own wrong tries; a cancel here starts no wait.
      expect(again.lock.wait, Duration.zero);
      harness.deviceAuth.answers.add(true);
      expect(await again.lock.unlockWithDevice('open'), isTrue);
      expect(again.lock.locked, isFalse);
      expect(harness.deviceAuth.reasons, [
        'turn on',
        'turn on',
        'open',
        'open',
        'open',
        'open',
        'open',
        'open',
        'open',
        'open',
        'open',
      ]);

      // Off only when the device says yes, too.
      harness.deviceAuth.answers.add(false);
      expect(await again.lock.removeWithDevice('turn off'), isFalse);
      expect(again.lock.enabled, isTrue);
      harness.deviceAuth.answers.add(true);
      expect(await again.lock.removeWithDevice('turn off'), isTrue);
      expect(again.lock.kind, LockKind.none);
      expect(await const FlutterSecureStorage().read(key: 'notelore.lock'), isNull);
    },
  );

  test('a long time in the device prompt does not lock again once it said yes (#295)', () async {
    // On Android the PIN or pattern screen is an activity of its own: Notelore
    // is in the background for as long as the person takes there.
    var now = DateTime.utc(2026, 10, 18, 12);
    final harness = Harness();
    final session = harness.session(clock: () => now);
    await session.lock.useDevice('turn on');
    final again = harness.session(clock: () => now);
    await again.lock.load();
    again.lock.backgrounded(); // the prompt opens
    now = now.add(const Duration(minutes: 3));
    expect(await again.lock.unlockWithDevice('open'), isTrue);
    again.lock.foregrounded(); // back from the prompt
    expect(again.lock.locked, isFalse);
  });

  test('a device without a lock of its own cannot use it (#295)', () async {
    final harness = Harness()..deviceAuth.hasLock = false;
    final session = harness.session();
    expect(await session.lock.deviceAvailable(), isFalse);
    expect(await session.lock.useDevice('turn on'), isFalse);
    expect(session.lock.enabled, isFalse);
    expect(harness.deviceAuth.reasons, isEmpty); // not even asked
  });

  test(
    'a Notelore pattern or PIN keeps its kind; an older lock reads as a password (#295)',
    () async {
      final harness = Harness();
      final session = harness.session();
      await session.lock.set('0-4-8-5', kind: LockKind.pattern);
      var again = harness.session();
      await again.lock.load();
      expect(again.lock.kind, LockKind.pattern);
      expect(await again.lock.unlock('0-4-8-5'), isTrue);

      await again.lock.set('2468', kind: LockKind.pin);
      again = harness.session();
      await again.lock.load();
      expect(again.lock.kind, LockKind.pin);

      // A lock set before #295 has a hash and no kind: it keeps working as it was.
      await const FlutterSecureStorage().delete(key: 'notelore.lock.kind');
      again = harness.session();
      await again.lock.load();
      expect(again.lock.kind, LockKind.password);
      expect(await again.lock.unlock('2468'), isTrue);
      expect(await again.lock.remove('2468'), isTrue);
      expect(await const FlutterSecureStorage().read(key: 'notelore.lock.kind'), isNull);
    },
  );

  test(
    'wrong tries: after five a growing wait, kept over a restart; the right one resets',
    () async {
      var now = DateTime.utc(2026, 10, 17, 12);
      final harness = Harness();
      final session = harness.session(clock: () => now);
      await session.lock.set('2468');
      for (var i = 0; i < 4; i++) {
        expect(await session.lock.unlock('0000'), isFalse);
        expect(session.lock.wait, Duration.zero);
      }
      expect(await session.lock.unlock('0000'), isFalse); // the fifth
      expect(session.lock.wait, const Duration(seconds: 30));
      expect(await session.lock.unlock('2468'), isFalse); // even the right one waits
      now = now.add(const Duration(seconds: 10));
      expect(session.lock.wait, const Duration(seconds: 20));
      // A restart does not wipe the count: it lives in the keystore. The wait
      // starts again in full, since after a restart only the clock knows how
      // long it ran, and the clock can be moved (#412).
      final again = harness.session(clock: () => now);
      await again.load();
      expect(again.lock.wait, const Duration(seconds: 30));
      now = now.add(const Duration(seconds: 30));
      expect(await again.lock.unlock('0000'), isFalse); // sixth
      expect(again.lock.wait, const Duration(minutes: 1));
      now = now.add(const Duration(minutes: 1));
      expect(await again.lock.unlock('0000'), isFalse); // seventh
      expect(again.lock.wait, const Duration(minutes: 5));
      now = now.add(const Duration(minutes: 5));
      expect(await again.lock.unlock('0000'), isFalse); // eighth: no longer than five minutes
      expect(again.lock.wait, const Duration(minutes: 5));
      now = now.add(const Duration(minutes: 5));
      expect(await again.lock.unlock('2468'), isTrue);
      expect(again.lock.wait, Duration.zero);
      expect(await const FlutterSecureStorage().read(key: 'notelore.lock.failures'), isNull);
    },
  );

  test('moving the clock ahead and restarting does not end a wait (#412)', () async {
    var now = DateTime.utc(2026, 10, 18, 12);
    var started = DateTime.utc(2026, 10, 18, 12); // this run's own time
    final harness = Harness();
    final session = harness.session(clock: () => now, uptime: () => now.difference(started));
    await session.lock.set('2468');
    for (var i = 0; i < 5; i++) {
      await session.lock.unlock('0000');
    }
    expect(session.lock.wait, const Duration(seconds: 30));
    // The app is killed, the phone's clock set a day ahead, the app opened.
    now = now.add(const Duration(days: 1));
    started = now;
    final again = harness.session(clock: () => now, uptime: () => now.difference(started));
    await again.load();
    expect(again.lock.wait, const Duration(seconds: 30));
    expect(await again.lock.unlock('2468'), isFalse); // the right one waits too
    now = now.add(const Duration(seconds: 30));
    expect(await again.lock.unlock('2468'), isTrue);
  });

  test('a new or removed lock starts with no failures; a damaged count is none', () async {
    final harness = Harness();
    final session = harness.session();
    await session.lock.set('2468');
    for (var i = 0; i < 5; i++) {
      await session.lock.unlock('0000');
    }
    expect(session.lock.wait, isNot(Duration.zero));
    await session.lock.set('1357'); // a new PIN, a clean slate
    expect(session.lock.wait, Duration.zero);
    expect(await const FlutterSecureStorage().read(key: 'notelore.lock.failures'), isNull);
    await session.lock.unlock('0000');
    expect(await session.lock.remove('1357'), isTrue);
    expect(await const FlutterSecureStorage().read(key: 'notelore.lock.failures'), isNull);
    await const FlutterSecureStorage().write(key: 'notelore.lock.failures', value: 'garbage');
    final again = harness.session();
    await again.load();
    expect(again.lock.wait, Duration.zero);
  });

  test('turning the lock off needs the current PIN; nothing else is touched', () async {
    final harness = Harness();
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    await session.lock.set('2468');
    expect(await session.lock.remove('0000'), isFalse);
    expect(session.lock.enabled, isTrue);
    expect(await session.lock.remove('2468'), isTrue);
    expect(session.lock.enabled, isFalse);
    expect(await const FlutterSecureStorage().read(key: 'notelore.lock'), isNull);
    expect(await const FlutterSecureStorage().read(key: 'notelore.anthropic.api_key'), 'k');
    final again = harness.session();
    await again.load();
    expect(again.lock.locked, isFalse);
    expect(again.ready, isTrue);
    expect(await again.lock.unlock('anything'), isTrue); // no lock: nothing to open
  });

  test('the wait after wrong tries holds when the clock is moved forward (#315)', () async {
    var now = DateTime.utc(2026, 10, 17, 12);
    var up = Duration.zero; // time that only moves forward, unlike the device clock
    final session = Harness().session(clock: () => now, uptime: () => up);
    await session.lock.set('2468');
    for (var i = 0; i < 5; i++) {
      await session.lock.unlock('0000');
    }
    expect(session.lock.wait, const Duration(seconds: 30));
    now = now.add(const Duration(hours: 1)); // the clock set ahead
    expect(session.lock.wait, const Duration(seconds: 30));
    expect(await session.lock.unlock('2468'), isFalse);
    up += const Duration(seconds: 30);
    expect(session.lock.wait, Duration.zero);
    expect(await session.lock.unlock('2468'), isTrue);
  });

  test('turning the lock off counts wrong tries and waits like opening it (#315)', () async {
    final now = DateTime.utc(2026, 10, 17, 12);
    final session = Harness().session(clock: () => now);
    await session.lock.set('2468');
    for (var i = 0; i < 5; i++) {
      expect(await session.lock.remove('0000'), isFalse);
    }
    expect(session.lock.wait, const Duration(seconds: 30));
    expect(await session.lock.remove('2468'), isFalse); // even the right one waits
    expect(session.lock.enabled, isTrue);
  });

  test('a development run keeps its own lock, apart from the real app', () async {
    final harness = Harness();
    final dev = harness.session(keySpace: 'notelore-dev');
    await dev.lock.set('2468');
    expect(await const FlutterSecureStorage().read(key: 'notelore-dev.lock'), isNotNull);
    expect(await const FlutterSecureStorage().read(key: 'notelore.lock'), isNull);
  });

  test('connections: every model with a key or a sign-in, kept across a switch (#356)', () async {
    final harness = Harness(chatGpt: FakeAuth());
    final session = harness.session();
    await session.load();
    expect(await session.connections(), isEmpty);
    await session.connect(findProvider('anthropic'), 'sk-ant');
    await session.connect(findProvider('ollama'), ''); // a desktop model, no key
    expect((await session.connections()).map((s) => s.name), ['anthropic', 'ollama']);
    expect(session.spec!.name, 'ollama');
    // Back to Claude with one tap: its stored key, checked again, no new entry.
    await session.switchTo(findProvider('anthropic'));
    expect(session.spec!.name, 'anthropic');
    expect(harness.created.last, ('anthropic', 'sk-ant', 'claude-sonnet-5-5'));
    // The ChatGPT plan counts once signed in.
    harness.chatGpt!.granted = true;
    expect((await session.connections()).map((s) => s.name), ['chatgpt', 'anthropic', 'ollama']);
  });

  test(
    'disconnect removes one model; the active one leaves no model, the notes stay (#356)',
    () async {
      final harness = Harness(chatGpt: FakeAuth()..granted = true, answers: ['hi']);
      final session = harness.session();
      await session.connect(findProvider('anthropic'), 'sk-ant');
      await session.send('x');
      // Not the active one: only its sign-in goes.
      await session.disconnect(findProvider('chatgpt'));
      expect(harness.chatGpt!.signedOut, isTrue);
      expect(session.spec!.name, 'anthropic');
      // The active one: its key goes, and no model until another is chosen.
      await session.disconnect(findProvider('anthropic'));
      expect(await const FlutterSecureStorage().read(key: 'notelore.anthropic.api_key'), isNull);
      expect(session.ready, isFalse);
      expect(session.spec, isNull);
      expect(session.transcript, isNotEmpty); // the conversation stays
      expect(await session.connections(), isEmpty);
      final again = harness.session();
      await again.load();
      expect(again.ready, isFalse);
    },
  );

  test('an Ollama set up before connections existed counts as connected (#356)', () async {
    final harness = Harness();
    await harness.session().connect(findProvider('ollama'), '');
    await const FlutterSecureStorage().delete(key: 'notelore.ollama.api_key'); // as before #356
    final again = harness.session();
    await again.load();
    expect((await again.connections()).map((s) => s.name), ['ollama']);
  });

  test('a message waiting when its model is removed goes out with the next one (#356)', () async {
    final harness = Harness(answers: [const NetworkError('offline'), 'Saved.']);
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'sk-ant');
    await session.send('remember the milk');
    expect(session.transcript.last.role, ChatRole.pending);
    await session.disconnect(findProvider('anthropic'));
    await session.retryNow(); // no model: it keeps waiting
    expect(session.transcript.last.role, ChatRole.pending);
    await session.connect(findProvider('openai'), 'sk-oa');
    await session.retryNow();
    expect(session.transcript.last, (role: ChatRole.assistant, text: 'Saved.'));
  });

  test('switching to a model whose key is gone says so and changes nothing (#356)', () async {
    final harness = Harness();
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'sk-ant');
    await expectLater(session.switchTo(findProvider('openai')), throwsA(isA<StateError>()));
    expect(session.spec!.name, 'anthropic');
  });

  test('a device set up once stays set up, across a restart, until logout (#363)', () async {
    final harness = Harness();
    final session = harness.session();
    await session.load();
    expect(session.setUpBefore, isFalse);
    await session.connect(findProvider('anthropic'), 'sk-ant');
    expect(session.setUpBefore, isTrue);
    await session.disconnect(findProvider('anthropic'));
    final again = harness.session();
    await again.load();
    expect(again.ready, isFalse);
    expect(again.setUpBefore, isTrue); // the app opens, asking for a model in the chat
    // No model: a send (a quick answer, a resend) does nothing, never a crash.
    await again.send('hello');
    expect(again.transcript, isEmpty);
    await again.logout();
    expect(again.setUpBefore, isFalse);
    final fresh = harness.session();
    await fresh.load();
    expect(fresh.setUpBefore, isFalse);
  });

  test('logout forgets the key, the provider and the conversation', () async {
    final harness = Harness(answers: ['hi']);
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    await session.send('x');
    session.draft = 'not sent';
    await session.logout();
    expect(session.ready, isFalse);
    expect(session.transcript, isEmpty);
    expect(session.draft, isEmpty); // the unsent text goes with the conversation
    expect(session.models, isEmpty);
    expect(await const FlutterSecureStorage().read(key: 'notelore.anthropic.api_key'), isNull);
    final again = harness.session();
    await again.load();
    expect(again.ready, isFalse);
  });

  test('a key lost after loading sends setModel back to setup', () async {
    final harness = Harness();
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    await const FlutterSecureStorage().delete(key: 'notelore.anthropic.api_key');
    await session.setModel('claude-x');
    expect(session.ready, isFalse);
    expect(session.spec, isNull);
  });

  test('logout forgets the keys of every provider', () async {
    final harness = Harness();
    final session = harness.session();
    await session.connect(findProvider('openai'), 'old');
    await session.connect(findProvider('anthropic'), 'new');
    await session.logout();
    final left = await const FlutterSecureStorage().readAll();
    expect(left, isEmpty);
  });

  test('a separate key space keeps a dev run away from the real keys', () async {
    final harness = Harness();
    final dev = Session(
      harness.paths,
      keySpace: 'notelore-dev',
      validate: (spec, key) async => <String>[],
      makeProvider: (spec, key, {model, planToken, webSearch = false}) => harness.provider,
    );
    addTearDown(dev.dispose);
    await dev.connect(findProvider('anthropic'), 'dev-key');
    final stored = await const FlutterSecureStorage().readAll();
    expect(stored, {'notelore-dev.anthropic.api_key': 'dev-key'});
  });

  test('a note saved with CRLF line endings reads like any other', () async {
    final harness = Harness();
    final session = harness.session();
    final path = createNote(harness.paths.notes.path, 'topic', 'Windows', today: today);
    File(path).writeAsStringSync(File(path).readAsStringSync().replaceAll('\n', '\r\n'));
    expect(session.readNote(session.listNotes().single), contains('\n# Windows\n'));
  });

  test('deleting a note moves it to the archive, and undo brings it back', () async {
    final harness = Harness();
    final session = harness.session();
    final path = createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    final original = File(path).readAsBytesSync();
    final note = session.listNotes().single;
    final archived = (await session.deleteNote(note))!;
    expect(
      archived,
      p.join(harness.paths.notes.path, '_archive', '2026-09-30', 'topics', 'kitaplar.md'),
    );
    expect(File(path).existsSync(), isFalse);
    expect(session.listNotes(), isEmpty);
    await session.restoreNote(note, archived);
    expect(File(path).readAsBytesSync(), original);
    expect(session.listNotes(), [note]);
    // A new note took the place meanwhile: undo never overwrites it.
    final again = (await session.deleteNote(note))!;
    expect(await session.deleteNote(note), isNull); // already gone: nothing to do
    File(path).writeAsStringSync('new');
    await session.restoreNote(note, again);
    expect(File(path).readAsStringSync(), 'new');
    expect(File(again).existsSync(), isTrue);
  });

  test('the archive: listed, read, restored; a taken name is refused', () async {
    final harness = Harness();
    final session = harness.session();
    final path = createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    await session.deleteNote(session.listNotes().single);
    final archived = session.listArchived().single;
    expect(archived.title, 'Kitaplar');
    expect(session.readArchived(archived), contains('\n# Kitaplar\n'));
    expect(await session.restoreArchived(archived), isTrue);
    expect(File(path).existsSync(), isTrue);
    expect(session.listArchived(), isEmpty);
    // Archived again, then a new note takes the name: restoring is refused.
    await session.deleteNote(session.listNotes().single);
    createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    expect(await session.restoreArchived(session.listArchived().single), isFalse);
    expect(session.listArchived(), hasLength(1));
  });

  test('the archive: one note deleted for good, then the rest (#438)', () async {
    final harness = Harness();
    final session = harness.session();
    final root = harness.paths.notes.path;
    createNote(root, 'topic', 'Kitaplar', today: today);
    createNote(root, 'topic', 'Filmler', today: today);
    for (final note in session.listNotes()) {
      await session.deleteNote(note);
    }
    final first = session.listArchived().first;
    await session.deleteArchived(first);
    expect(File(first.path).existsSync(), isFalse);
    expect(session.listArchived(), hasLength(1));
    // One already gone (a sync, or by hand) is no error.
    final second = session.listArchived().single;
    File(second.path).copySync('${second.path}.kept');
    File(second.path).deleteSync();
    await session.deleteArchived(second);
    File('${second.path}.kept').renameSync(second.path);
    expect(await session.emptyArchive(), 1);
    expect(session.listArchived(), isEmpty);
    // No empty dated folders are left behind.
    expect(Directory(p.join(root, '_archive')).listSync(), isEmpty);
    expect(await session.emptyArchive(), 0);
  });

  test('withoutFrontMatter shows a note from its title down', () {
    expect(withoutFrontMatter('---\ntitle: T\n---\n# T\nbody\n'), '# T\nbody\n');
    expect(withoutFrontMatter('# Plain\n'), '# Plain\n');
    expect(withoutFrontMatter('---\nunterminated'), '---\nunterminated');
  });

  test('an original that cannot be written is skipped; the words still go (#279)', () {
    final harness = Harness();
    final session = harness.session();
    File(p.join(harness.paths.notes.path, 'attachments'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('in the way'); // a file where the folder would go
    expect(session.keepOriginal('memo.wav', [1]), isNull);
  });

  test('a failed image send discards its original and its marker (#534)', () async {
    final harness = Harness(answers: [const NetworkError('offline')]);
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    final path = session.keepOriginal('r.png', [1, 2, 3])!;
    const start = 'what is it\n\n<attached image="r.png"';
    final sent = await session.send(
      '$start original="$path"/>',
      images: [
        imageBlock('image/png', [1, 2, 3]),
      ],
    );
    expect(sent, isFalse);
    session.discardOriginal(path);
    expect(File(p.joinAll([harness.paths.notes.path, ...path.split('/')])).existsSync(), isFalse);
    expect(session.transcript.first.text, '$start/>');
  });

  test('discarding an original that is already gone is harmless (#534)', () {
    final session = Harness().session();
    session.discardOriginal('attachments/2026-10-22/missing.png');
  });

  test('a later failed message does not drop a delivered image original (#534)', () async {
    final first = Completer<AgentResponse>();
    final harness = Harness(answers: [first.future, const NetworkError('offline')]);
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    final path = session.keepOriginal('r.png', [1, 2, 3])!;
    final sent = session.send(
      'what is it\n\n<attached image="r.png" original="$path"/>',
      images: [
        imageBlock('image/png', [1, 2, 3]),
      ],
    );
    await session.send('follow-up'); // joins while the image turn runs
    first.complete(
      const AgentResponse([
        {'type': 'text', 'text': 'A receipt.'},
      ], 'end_turn'),
    );
    expect(await sent, isTrue);
    expect(session.transcript.first.text, contains('original="$path"'));
    expect(File(p.joinAll([harness.paths.notes.path, ...path.split('/')])).existsSync(), isTrue);
  });

  test('images do not join a running turn or the queue (#278)', () async {
    final first = Completer<AgentResponse>();
    final harness = Harness(answers: [first.future]);
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    final running = session.send('one');
    const message = 'what is it\n\n<attached image="r.png"/>';
    final sent = await session.send(
      message,
      images: [
        imageBlock('image/png', [1, 2, 3]),
      ],
    );
    expect(sent, isFalse);
    expect(session.transcript.map((l) => l.text), ['one']);
    first.complete(
      const AgentResponse([
        {'type': 'text', 'text': 'Done.'},
      ], 'end_turn'),
    );
    await running;
    expect(session.transcript.map((l) => l.role), [ChatRole.user, ChatRole.assistant]);
  });
}

/// A keystore whose delete fails, like a locked one.
class _BrokenDelete extends FlutterSecureStorage {
  const _BrokenDelete();

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) => throw Exception('keystore locked');
}

/// A periodic timer that never fires by itself: the test calls its tick.
class _Ticker implements Timer {
  @override
  void cancel() {}

  @override
  bool get isActive => true;

  @override
  int get tick => 0;
}
