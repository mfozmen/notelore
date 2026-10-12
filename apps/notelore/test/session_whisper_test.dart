import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  test(
    'the device recognizer until Whisper is downloaded; then Whisper, unless turned off',
    () async {
      final harness = Harness();
      final session = harness.session();
      expect(session.speech, same(harness.speech));
      expect(session.whisper.ready, isFalse);

      final progress = <double?>[];
      session.addListener(() => progress.add(session.whisperProgress));
      await session.downloadWhisper();
      expect(session.whisper.ready, isTrue);
      expect(session.whisperProgress, isNull);
      expect(progress, contains(1.0));
      expect(session.speech, same(harness.whisper));

      session.setUseWhisper(false);
      expect(session.speech, same(harness.speech));
      // Remembered on this device.
      final again = harness.session();
      await again.load();
      expect(again.useWhisper, isFalse);
      again.setUseWhisper(true);
      expect(again.speech, same(harness.whisper));
    },
  );

  test('the microphone Whisper records from: the default, or the one picked, remembered', () async {
    final harness = Harness()..microphones = [(id: 'usb', label: 'USB mic')];
    final session = harness.session();
    expect(await session.listMicrophones(), [(id: 'usb', label: 'USB mic')]);
    await session.downloadWhisper();
    expect(session.speech, same(harness.whisper));
    expect(harness.chosenMicrophone!(), isNull); // the system default
    session.setMicrophone('usb');
    expect(harness.chosenMicrophone!(), 'usb'); // the next listen uses it
    final again = harness.session();
    await again.load();
    expect(again.microphone, 'usb');
  });

  test('a failed download says why and keeps nothing; a second tap while running waits', () async {
    final harness = Harness()..modelPage = null;
    final session = harness.session();
    final first = session.downloadWhisper();
    await session.downloadWhisper(); // already running: nothing more
    await first;
    expect(session.whisperProblem, contains('HTTP 404'));
    expect(session.whisper.ready, isFalse);
    expect(Directory(session.whisper.dir).listSync(), isEmpty);

    harness.modelPage = 'whisper bytes';
    await session.downloadWhisper();
    expect(session.whisperProblem, isNull);
    expect(session.whisper.ready, isTrue);
  });
}
