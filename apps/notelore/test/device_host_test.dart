import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/device_host.dart';
import 'package:notelore/src/whisper_model.dart';
import 'package:notelore_core/notelore_core.dart';

import 'support.dart';

void main() {
  late List<FakeDeviceEngine> made;
  late DeviceModelHost host;

  setUp(() {
    made = [];
    host = DeviceModelHost(
      model: WhisperModel(Directory.systemTemp.path, files: const []),
      file: () => 'model.gguf',
      makeEngine: (path) => (made..add(FakeDeviceEngine())).last,
      exclusive: <T>(Future<T> Function() task) => task(),
      fetch: (progress, problem) async {},
    );
  });

  test('every provider runs on one engine, and free lets it go (#659)', () async {
    expect(host.loaded, isFalse);
    host.provider('a');
    host.provider('b');
    expect(made, hasLength(1));
    expect(host.loaded, isTrue);
    await host.free();
    expect(made.single.disposed, 1);
    expect(host.loaded, isFalse);
  });

  test('a prefill runs once per prompt; cancelled, it does not run', () async {
    host.provider('a');
    host.startPrefill('system', slimTools);
    expect(host.preparing, isTrue);
    await pumpEventQueue();
    expect(made.single.prefilled, hasLength(1));
    expect(host.preparing, isFalse);
    host.startPrefill('system', slimTools);
    await pumpEventQueue();
    expect(made.single.prefilled, hasLength(1), reason: 'the same prompt is already read');
    host.startPrefill('other', slimTools);
    host.cancelPrefill();
    await pumpEventQueue();
    expect(made.single.prefilled, hasLength(1));
    expect(host.preparing, isFalse);
  });

  test('one download at a time', () async {
    final gate = Completer<void>();
    var runs = 0;
    final waiting = DeviceModelHost(
      model: WhisperModel(Directory.systemTemp.path, files: const []),
      file: () => 'model.gguf',
      makeEngine: (_) => FakeDeviceEngine(),
      exclusive: <T>(Future<T> Function() task) => task(),
      fetch: (progress, problem) {
        runs++;
        progress(0.5);
        return gate.future;
      },
    );
    final first = waiting.download();
    final second = waiting.download();
    expect(waiting.downloading, isNotNull);
    expect(waiting.progress, 0.5);
    gate.complete();
    await Future.wait([first, second]);
    expect(runs, 1);
    expect(waiting.downloading, isNull);
  });
}
