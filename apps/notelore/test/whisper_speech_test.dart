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

class FakeTranscriber implements Transcriber {
  FakeTranscriber(this.text);

  final String text;
  final heard = <(List<double>, String)>[];

  @override
  Future<String> transcribe(Float32List samples, String language) async {
    heard.add((samples.toList(), language));
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
  test('push to talk: everything recorded until finish is transcribed in the language', () async {
    final mic = FakeMicrophone();
    final transcriber = FakeTranscriber(' Bugün kitap okudum. ');
    final speech = WhisperSpeech(microphone: mic, transcriber: transcriber);
    final heard = speech.listen('tr');
    await pumpEventQueue();
    mic.chunks
      ..add(pcm([16384, -16384]))
      ..add(pcm([0, 32767, 1]).sublist(0, 5)); // half a sample at the end is dropped
    await pumpEventQueue();
    await speech.finish();
    expect(await heard, 'Bugün kitap okudum.');
    expect(transcriber.heard.single.$1, [0.5, -0.5, 0, 32767 / 32768]); // 16-bit as -1..1
    expect(transcriber.heard.single.$2, 'tr');
    expect(mic.stopped, 1);
  });

  test('a cancel, nothing recorded, or nothing understood is no phrase', () async {
    final mic = FakeMicrophone();
    final transcriber = FakeTranscriber('  ');
    final speech = WhisperSpeech(microphone: mic, transcriber: transcriber);
    final cancelled = speech.listen('en');
    await pumpEventQueue();
    mic.chunks.add(pcm([1, 2]));
    await speech.cancel();
    expect(await cancelled, isNull);

    final empty = speech.listen('en');
    await pumpEventQueue();
    await speech.finish(); // released at once: nothing was said
    expect(await empty, isNull);

    final mumbled = speech.listen('en');
    await pumpEventQueue();
    mic.chunks.add(pcm([1, 2]));
    await pumpEventQueue();
    await speech.finish();
    expect(await mumbled, isNull);
    expect(transcriber.heard, hasLength(1)); // only the mumble reached Whisper
    await speech.cancel(); // nothing running: nothing happens
  });

  test('a button held too long ends the recording by itself', () async {
    final mic = FakeMicrophone();
    final speech = WhisperSpeech(
      microphone: mic,
      transcriber: FakeTranscriber('long'),
      longest: const Duration(milliseconds: 20),
    );
    final heard = speech.listen('en');
    await pumpEventQueue();
    mic.chunks.add(pcm([1]));
    expect(await heard, 'long');
  });

  test('a microphone that fails says so', () async {
    final broken = FakeMicrophone();
    final speech = WhisperSpeech(microphone: broken, transcriber: FakeTranscriber('x'));
    final failed = speech.listen('en');
    await pumpEventQueue();
    broken.chunks.addError(Exception('device lost'));
    await expectLater(failed, throwsA(isA<ListenFailed>()));

    broken.refuse = const VoiceUnavailable();
    await expectLater(speech.listen('en'), throwsA(isA<VoiceUnavailable>()));
  });
}
