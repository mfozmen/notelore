import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/session.dart';
import 'package:notelore_core/notelore_core.dart';

import 'support.dart';

void main() {
  test('the model on the device is offered only where it can run (#328)', () {
    expect(Harness().session().providers.map((s) => s.name), isNot(contains('device')));
    expect(Harness().session(deviceModels: true).providers.map((s) => s.name), contains('device'));
  });

  test('download it once, checked, then talk to it: nothing leaves the device', () async {
    final harness = Harness();
    final session = harness.session(deviceModels: true);
    final device = findProvider('device');
    // Not downloaded yet: nothing to connect to.
    await expectLater(session.connect(device, ''), throwsA(isA<TransientValidationError>()));
    harness.pages['https://models.test/q.gguf'] = 'model bytes';
    await session.downloadDeviceModel();
    expect(session.deviceModel.ready, isTrue);
    expect(session.deviceProgress, isNull);
    expect(session.deviceProblem, isNull);
    await session.connect(device, '');
    expect(session.model, 'qwen3-4b-instruct-2507');
    harness.deviceEngine.answers.add({
      'message': {'content': 'Saved.'},
    });
    await session.send('Mopsos: weekly.');
    expect(session.transcript.last.text, 'Saved.');
    // The engine runs the file just downloaded, with Notelore's prompt and tools.
    expect(harness.enginePaths.single, session.deviceModel.path('q.gguf'));
    final (messages, tools) = harness.deviceEngine.asked.single;
    expect(messages.first['role'], 'system');
    expect(messages.last, {'role': 'user', 'content': 'Mopsos: weekly.'});
    expect(tools, isNotEmpty);
    expect(harness.created, isEmpty); // no network provider was made
    // Connected on this device: chosen again without asking.
    expect((await session.connections()).map((s) => s.name), ['device']);
  });

  test('a download that fails or does not match keeps nothing and says why', () async {
    final harness = Harness();
    final session = harness.session(deviceModels: true);
    harness.pages['https://models.test/q.gguf'] = 'other bytes';
    await session.downloadDeviceModel();
    expect(session.deviceModel.ready, isFalse);
    expect(session.deviceProblem, isNotNull);
    // A second tap while one runs starts no second download.
    harness.pages['https://models.test/q.gguf'] = 'model bytes';
    await Future.wait([session.downloadDeviceModel(), session.downloadDeviceModel()]);
    expect(session.deviceModel.ready, isTrue);
  });

  test('one engine at a time: a rebuild reuses it, leaving the model frees it (#328)', () async {
    final harness = Harness();
    final session = harness.session(deviceModels: true);
    harness.pages['https://models.test/q.gguf'] = 'model bytes';
    await session.downloadDeviceModel();
    final device = findProvider('device');
    await session.connect(device, '');
    await session.setWebSearch(false); // rebuilds the provider
    await session.switchTo(device);
    expect(harness.enginePaths, hasLength(1)); // never a second 2.5 GB copy in memory
    expect(harness.deviceEngine.disposed, 0);
    // Removed: the engine goes, and the 2.5 GB file with it.
    await session.disconnect(device);
    expect(harness.deviceEngine.disposed, 1);
    expect(session.deviceModel.ready, isFalse);
    expect(Directory(session.deviceModel.dir).existsSync(), isFalse);
  });

  test('removed while it downloads: the download ends first, then nothing is left', () async {
    final harness = Harness();
    final session = harness.session(deviceModels: true);
    final served = Completer<String>();
    harness.pages['https://models.test/q.gguf'] = served.future;
    final downloading = session.downloadDeviceModel();
    final again = session.downloadDeviceModel(); // the same download, not a second
    final removing = session.disconnect(findProvider('device'));
    served.complete('model bytes');
    await Future.wait([downloading, again, removing]);
    expect(session.deviceModel.ready, isFalse);
    expect(Directory(session.deviceModel.dir).existsSync(), isFalse);
    expect(session.deviceProgress, isNull);
    expect(session.deviceProblem, isNull); // it finished, then went: no failure to show
  });

  test('another model, or closing, frees the one on the device', () async {
    final harness = Harness();
    final session = harness.session(deviceModels: true, owned: false);
    harness.pages['https://models.test/q.gguf'] = 'model bytes';
    await session.downloadDeviceModel();
    await session.connect(findProvider('device'), '');
    await session.connect(findProvider('anthropic'), 'k');
    expect(harness.deviceEngine.disposed, 1);
    expect(session.deviceModel.ready, isTrue); // only removing it deletes the file
    await session.connect(findProvider('device'), '');
    session.dispose();
    expect(harness.deviceEngine.disposed, 2);
  });

  test('another device on the model of its own does not move this one there', () async {
    final harness = Harness(auth: FakeAuth());
    harness.remote.texts[sharedSettings] = jsonEncode({
      'updated': DateTime.utc(2030).toIso8601String(),
      'provider': 'device',
      'model': 'qwen3-4b-instruct-2507',
    });
    final session = harness.session(deviceModels: true);
    await session.connectDrive();
    expect(session.spec, isNull); // the file is on the other device, not here
  });

  test('the model on the device is asked with the slim prompt and tools (#447)', () async {
    final harness = Harness();
    final session = harness.session(deviceModels: true);
    harness.pages['https://models.test/q.gguf'] = 'model bytes';
    await session.downloadDeviceModel();
    await session.connect(findProvider('device'), '');
    harness.deviceEngine.answers.add({
      'message': {'content': 'Hello.'},
    });
    await session.send('hi');
    final (messages, tools) = harness.deviceEngine.asked.single;
    expect(messages.first['content'], contains('Dictated sound-alike'));
    expect(tools, hasLength(slimTools.length));
  });

  test('the device model reads its prompt and tools before the first message (#595)', () async {
    final harness = Harness();
    final session = harness.session(deviceModels: true);
    harness.pages['https://models.test/q.gguf'] = 'model bytes';
    await session.downloadDeviceModel();
    await session.connect(findProvider('device'), '');
    expect(session.preparing, isTrue);
    await session.syncDone;
    expect(session.preparing, isFalse);
    final (system, tools) = harness.deviceEngine.prefilled.single;
    expect(system, contains('Dictated sound-alike'));
    expect(tools, hasLength(slimTools.length));
    expect(harness.deviceEngine.asked, isEmpty); // no turn yet
  });

  test('a message sent while the prompt is read waits for it, and runs once (#595)', () async {
    final harness = Harness();
    final session = harness.session(deviceModels: true);
    harness.pages['https://models.test/q.gguf'] = 'model bytes';
    await session.downloadDeviceModel();
    final gate = Completer<void>();
    harness.deviceEngine.prefillGate = gate.future;
    await session.connect(findProvider('device'), '');
    harness.deviceEngine.answers.add({
      'message': {'content': 'Saved.'},
    });
    final sent = session.send('Mopsos: weekly.');
    expect(session.busy, isTrue);
    expect(session.transcript.last, (role: ChatRole.user, text: 'Mopsos: weekly.'));
    expect(harness.deviceEngine.asked, isEmpty);
    gate.complete();
    expect(await sent, isTrue);
    expect(session.preparing, isFalse);
    expect(harness.deviceEngine.prefilled, hasLength(1));
    expect(harness.deviceEngine.asked, hasLength(1));
    expect(session.transcript.last.text, 'Saved.');
  });

  test('a prefill that fails does not fail the first turn (#595)', () async {
    final harness = Harness();
    final session = harness.session(deviceModels: true);
    harness.pages['https://models.test/q.gguf'] = 'model bytes';
    await session.downloadDeviceModel();
    harness.deviceEngine.prefillFailure = const LocalModelFailed('out of memory');
    await session.connect(findProvider('device'), '');
    await session.syncDone;
    expect(session.preparing, isFalse);
    harness.deviceEngine.answers.add({
      'message': {'content': 'Saved.'},
    });
    await session.send('Mopsos: weekly.');
    expect(session.transcript.last.text, 'Saved.');
    expect(harness.deviceEngine.asked, hasLength(1));
  });

  test('the same prompt and tools are not read again after a rebuild (#595)', () async {
    final harness = Harness();
    final session = harness.session(deviceModels: true);
    harness.pages['https://models.test/q.gguf'] = 'model bytes';
    await session.downloadDeviceModel();
    await session.connect(findProvider('device'), '');
    await session.syncDone;
    expect(harness.deviceEngine.prefilled, hasLength(1));
    await session.setWebSearch(false); // rebuilds the provider, same engine and prompt
    await session.syncDone;
    expect(harness.deviceEngine.prefilled, hasLength(1));
  });

  test('the setup test turn does not replace the prefill (#595)', () async {
    final harness = Harness();
    final session = harness.session(deviceModels: true);
    harness.pages['https://models.test/q.gguf'] = 'model bytes';
    await session.downloadDeviceModel();
    session.finishingSetup = true;
    await session.connect(findProvider('device'), '');
    await session.syncDone;
    expect(harness.deviceEngine.prefilled, isEmpty); // the test turn comes first
    session.finishSetup();
    await session.syncDone;
    expect(harness.deviceEngine.prefilled, hasLength(1));
  });

  test('a device that cannot run the model says so in the chat', () async {
    final harness = Harness();
    final session = harness.session(deviceModels: true);
    harness.pages['https://models.test/q.gguf'] = 'model bytes';
    await session.downloadDeviceModel();
    await session.connect(findProvider('device'), '');
    harness.deviceEngine.failure = const LocalModelFailed('out of memory');
    await session.send('hi');
    expect(session.transcript.last.role, ChatRole.error);
    expect(session.transcript.last.text, contains('could not run the model'));
  });
}
