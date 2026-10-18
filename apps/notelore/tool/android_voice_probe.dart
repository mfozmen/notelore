/// Checks voice mode's device side on Android (#163): the speech recognizer,
/// the microphone permission and a recording stream, with no account, no
/// model provider and no notes. Run it on a device or emulator:
///
///     flutter run -d <device> -t tool/android_voice_probe.dart
///
/// and read the `voice probe:` lines in the log.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:notelore/src/whisper_model.dart';
import 'package:notelore/src/whisper_native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';

void say(String line) => debugPrint('voice probe: $line');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('Running the voice probe; see the log.')),
    ),
  );

  final speech = SpeechToText();
  try {
    final ready = await speech.initialize(
      onStatus: (s) => say('status $s'),
      onError: (e) => say('error ${e.errorMsg} (permanent: ${e.permanent})'),
      options: [SpeechToText.androidNoBluetooth],
    );
    say('speech_to_text initialize: $ready');
    if (ready) {
      final locales = await speech.locales();
      say(
        'locales: ${locales.length}, tr_TR ${locales.any((l) => l.localeId.startsWith('tr'))}, '
        'en_US ${locales.any((l) => l.localeId.startsWith('en'))}',
      );
      await speech.listen(
        onResult: (r) => say('result ${r.recognizedWords.length} chars, final ${r.finalResult}'),
        listenOptions: SpeechListenOptions(localeId: 'en_US', listenMode: ListenMode.dictation),
      );
      say('listening: ${speech.isListening}');
      await Future<void>.delayed(const Duration(seconds: 3));
      await speech.stop();
    }
  } on Object catch (error) {
    say('speech_to_text threw: $error');
  }

  final recorder = AudioRecorder();
  try {
    say('record hasPermission: ${await recorder.hasPermission()}');
    final devices = await recorder.listInputDevices();
    say('record input devices: ${devices.map((d) => d.label).toList()}');
    final stream = await recorder.startStream(
      const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1),
    );
    var bytes = 0;
    final sub = stream.listen((chunk) => bytes += chunk.length);
    await Future<void>.delayed(const Duration(seconds: 2));
    await recorder.stop();
    await sub.cancel();
    say('record stream: $bytes bytes in 2 s');
  } on Object catch (error) {
    say('record threw: $error');
  } finally {
    await recorder.dispose();
  }

  // On-device Whisper, as the app uses it once its model is there: the model
  // (about 375 MB, once) into the app's own support folder, then a held press.
  try {
    final dir = p.join((await getApplicationSupportDirectory()).path, 'probe-whisper');
    final model = WhisperModel(dir);
    if (!model.ready) {
      say('whisper: downloading the model');
      var shown = -1;
      await model.download(
        client: http.Client(),
        onProgress: (done) {
          final tenth = (done * 10).floor();
          if (tenth != shown) say('whisper: ${tenth * 10}%');
          shown = tenth;
        },
      );
    }
    final whisper = nativeWhisper(model, () => null);
    final heard = whisper.listen('en');
    await Future<void>.delayed(const Duration(seconds: 3));
    final clock = Stopwatch()..start();
    await whisper.finish();
    say('whisper heard: "${await heard}" (${clock.elapsedMilliseconds} ms after letting go)');
  } on Object catch (error) {
    say('whisper threw: $error');
  }
  say('done');
}
