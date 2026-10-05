import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/session.dart';
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
  });

  test('logout forgets the key, the provider and the conversation', () async {
    final harness = Harness(answers: ['hi']);
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    await session.send('x');
    await session.logout();
    expect(session.ready, isFalse);
    expect(session.transcript, isEmpty);
    expect(await const FlutterSecureStorage().read(key: 'notelore.anthropic.api_key'), isNull);
    final again = harness.session();
    await again.load();
    expect(again.ready, isFalse);
  });

  test('withoutFrontMatter shows a note from its title down', () {
    expect(withoutFrontMatter('---\ntitle: T\n---\n# T\nbody\n'), '# T\nbody\n');
    expect(withoutFrontMatter('# Plain\n'), '# Plain\n');
    expect(withoutFrontMatter('---\nunterminated'), '---\nunterminated');
  });
}
