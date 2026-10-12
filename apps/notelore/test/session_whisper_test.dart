import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/session.dart';

import 'support.dart';

void main() {
  /// Until the background download started by `load` is over.
  Future<void> downloaded(Session session) async {
    while (session.whisperProgress != null) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test(
    'opening the app downloads Whisper when it is missing; voice mode uses it once there',
    () async {
      final harness = Harness()..modelPage = 'whisper bytes';
      final session = harness.session();
      expect(session.speech, same(harness.speech)); // the device's, until then
      final progress = <double?>[];
      session.addListener(() => progress.add(session.whisperProgress));
      await session.load();
      await downloaded(session);
      expect(session.whisper.ready, isTrue);
      expect(progress, contains(1.0));
      expect(session.speech, same(harness.whisper));

      // The next start has it: nothing is downloaded again.
      harness.modelPage = null;
      final again = harness.session();
      await again.load();
      expect(again.whisperProgress, isNull);
      expect(again.whisperProblem, isNull);
      expect(again.speech, same(harness.whisper));
    },
  );

  test('the microphone Whisper records from: the default, or the one picked, remembered', () async {
    final harness = Harness()
      ..modelPage = 'whisper bytes'
      ..microphones = [(id: 'usb', label: 'USB mic')];
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
