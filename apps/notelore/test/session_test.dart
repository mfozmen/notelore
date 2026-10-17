import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test('Ollama needs no key', () async {
    final harness = Harness();
    await harness.session().connect(findProvider('ollama'), '');
    final again = harness.session();
    await again.load();
    expect(again.ready, isTrue);
    expect(harness.created.last, ('ollama', '', 'llama3.2'));
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
    final harness = Harness(answers: ['Okudum.', const NetworkError('offline'), 'Tamam.']);
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    await session.send('kitaplarım ne');
    await session.deleteNote(session.listNotes().single);
    await session.send('peki'); // fails: the model never answered it
    await session.send('şimdi');
    expect(harness.provider.asked.last, allOf(contains('şimdi'), contains('Kitaplar')));
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
      answers: [first.future, const NetworkError('offline'), 'Yazarı Can Dündar.'],
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
    final harness = Harness(answers: [const NetworkError('offline'), 'back']);
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    await session.send('one');
    expect(session.transcript.last.role, ChatRole.error);
    expect(session.transcript.last.text, contains('offline'));
    await session.send('two');
    expect(session.transcript.last.text, 'back');
  });

  test('resend sends the last message again, exactly, also after a failure', () async {
    final harness = Harness(answers: [const NetworkError('offline'), 'back']);
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
        ], 'tool_use'),
        const NetworkError('offline'), // the note is written, the answer fails
      ],
    );
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    await session.send('note Mopsos');
    expect(session.transcript.last.role, ChatRole.error);
    expect(session.transcript.last.text, contains('offline'));
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
    expect(session.readNote(notes.single), startsWith('# Mopsos\n'));
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
    // Ollama's list is the machine's own: a blank goes back to its fixed default.
    await session.connect(findProvider('ollama'), '');
    await session.setModel('');
    expect(session.model, 'llama3.2');
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

  test('logout forgets the key, the provider and the conversation', () async {
    final harness = Harness(answers: ['hi']);
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    await session.send('x');
    await session.logout();
    expect(session.ready, isFalse);
    expect(session.transcript, isEmpty);
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
    expect(session.readNote(session.listNotes().single), startsWith('# Windows\n'));
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
    expect(session.readArchived(archived), startsWith('# Kitaplar'));
    expect(await session.restoreArchived(archived), isTrue);
    expect(File(path).existsSync(), isTrue);
    expect(session.listArchived(), isEmpty);
    // Archived again, then a new note takes the name: restoring is refused.
    await session.deleteNote(session.listNotes().single);
    createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    expect(await session.restoreArchived(session.listArchived().single), isFalse);
    expect(session.listArchived(), hasLength(1));
  });

  test('withoutFrontMatter shows a note from its title down', () {
    expect(withoutFrontMatter('---\ntitle: T\n---\n# T\nbody\n'), '# T\nbody\n');
    expect(withoutFrontMatter('# Plain\n'), '# Plain\n');
    expect(withoutFrontMatter('---\nunterminated'), '---\nunterminated');
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
