import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/voice.dart';
import 'package:notelore/src/whisper_speech.dart';

class FakeMicrophone implements Microphone {
  /// The current recording; a new one on every start, as a real recorder does.
  var chunks = StreamController<Uint8List>();
  var started = 0;
  var stopped = 0;
  Object? refuse;

  @override
  Future<Stream<Uint8List>> start() async {
    if (refuse case final error?) throw error;
    started++;
    chunks = StreamController<Uint8List>();
    return chunks.stream;
  }

  @override
  Future<void> stop() async => stopped++;
}

/// Ends a phrase after [after] windows, returning everything it was fed.
class FakeDetector implements PhraseDetector {
  FakeDetector({this.after = 2});

  final int after;
  @override
  var speaking = false;
  final fed = <double>[];
  var windows = 0;
  var resets = 0;

  @override
  int get window => 4;

  @override
  Float32List? accept(Float32List samples) {
    fed.addAll(samples);
    windows++;
    return windows == after ? Float32List.fromList(fed) : null;
  }

  @override
  void reset() {
    resets++;
    windows = 0; // what was fed stays, for the test to read
  }
}

class FakeTranscriber implements Transcriber {
  FakeTranscriber(this.text);

  final String text;
  final heard = <(int, String)>[];

  @override
  Future<String> transcribe(Float32List samples, String language) async {
    heard.add((samples.length, language));
    return text;
  }
}

/// [values] as little-endian 16-bit PCM.
Uint8List pcm(List<int> values) {
  final data = ByteData(values.length * 2);
  for (final (i, v) in values.indexed) {
    data.setInt16(i * 2, v, Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  test('a phrase: windows fed to the detector, then transcribed in the language', () async {
    final mic = FakeMicrophone();
    final detector = FakeDetector();
    final transcriber = FakeTranscriber(' Bugün kitap okudum. ');
    final speech = WhisperSpeech(microphone: mic, detector: detector, transcriber: transcriber);
    final heard = speech.listen('tr');
    await pumpEventQueue();
    mic.chunks
      ..add(pcm([16384, -16384, 0])) // half a window: waits for more
      ..add(pcm([32767, 0, 0, 0, 0]));
    expect(await heard, 'Bugün kitap okudum.');
    expect(transcriber.heard, [(8, 'tr')]);
    expect(detector.fed.take(2), [0.5, -0.5]); // 16-bit samples as -1..1
    expect(mic.stopped, 1);
    expect(detector.resets, 1);
  });

  test('silence for too long ends with nothing; a cancel too', () async {
    final mic = FakeMicrophone();
    final speech = WhisperSpeech(
      microphone: mic,
      detector: FakeDetector(after: 100),
      transcriber: FakeTranscriber('x'),
      silence: const Duration(milliseconds: 20),
    );
    expect(await speech.listen('en'), isNull);
    final cancelled = speech.listen('en');
    await pumpEventQueue();
    await speech.cancel();
    expect(await cancelled, isNull);
    expect(mic.stopped, 2);
    await speech.cancel(); // nothing running: nothing happens
  });

  test('a long phrase is not cut off by the silence timeout', () async {
    final mic = FakeMicrophone();
    final speech = WhisperSpeech(
      microphone: mic,
      detector: FakeDetector(after: 3)..speaking = true,
      transcriber: FakeTranscriber('a long story'),
      silence: const Duration(milliseconds: 30),
    );
    final heard = speech.listen('en');
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      mic.chunks.add(pcm([1, 2, 3, 4]));
    }
    expect(await heard, 'a long story');
  });

  test('an empty transcription is silence; a microphone that fails says so', () async {
    final mic = FakeMicrophone();
    final speech = WhisperSpeech(
      microphone: mic,
      detector: FakeDetector(after: 1),
      transcriber: FakeTranscriber('  '),
    );
    final heard = speech.listen('en');
    await pumpEventQueue();
    mic.chunks.add(pcm([1, 2, 3, 4]));
    expect(await heard, isNull);

    final broken = FakeMicrophone();
    final failing = WhisperSpeech(
      microphone: broken,
      detector: FakeDetector(),
      transcriber: FakeTranscriber('x'),
    );
    final failed = failing.listen('en');
    await pumpEventQueue();
    broken.chunks.addError(Exception('device lost'));
    await expectLater(failed, throwsA(isA<ListenFailed>()));

    broken.refuse = const VoiceUnavailable();
    await expectLater(failing.listen('en'), throwsA(isA<VoiceUnavailable>()));
  });
}
