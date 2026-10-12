/// Speech recognition inside the app: the microphone's audio goes through a
/// voice-activity detector until a phrase ends, then Whisper writes it down.
/// Offline and free, the same in every language and on every platform (the
/// device recognizers differ: Windows' cannot do Turkish at all).
library;

import 'dart:async';
import 'dart:typed_data';

import 'voice.dart';

/// 16 kHz, mono, 16-bit PCM from the microphone.
abstract interface class Microphone {
  /// Throws [VoiceUnavailable] without a microphone or its permission.
  Future<Stream<Uint8List>> start();

  Future<void> stop();
}

/// Finds where a spoken phrase ends.
abstract interface class PhraseDetector {
  /// How many samples [accept] takes at a time.
  int get window;

  /// Takes one [window] of samples; returns the phrase once it has ended.
  Float32List? accept(Float32List samples);

  void reset();
}

/// Turns a phrase into text.
abstract interface class Transcriber {
  Future<String> transcribe(Float32List samples, String language);
}

class WhisperSpeech implements Speech {
  WhisperSpeech({
    required this.microphone,
    required this.detector,
    required this.transcriber,
    this.silence = const Duration(seconds: 15),
  });

  final Microphone microphone;
  final PhraseDetector detector;
  final Transcriber transcriber;

  /// How long to wait for a phrase before giving up (silence).
  final Duration silence;

  Completer<Float32List?>? _phrase;

  @override
  Future<String?> listen(String language) async {
    final phrase = _phrase = Completer<Float32List?>();
    final audio = await microphone.start();
    final pending = <double>[];
    final timer = Timer(silence, () => _end(null));
    final listening = audio.listen(
      (bytes) {
        pending.addAll(_samples(bytes));
        while (pending.length >= detector.window && !phrase.isCompleted) {
          final window = Float32List.fromList(pending.sublist(0, detector.window));
          pending.removeRange(0, detector.window);
          if (detector.accept(window) case final done?) _end(done);
        }
      },
      onError: (Object error) {
        if (!phrase.isCompleted) phrase.completeError(ListenFailed('$error'));
      },
    );
    try {
      final samples = await phrase.future;
      if (samples == null) return null;
      final text = (await transcriber.transcribe(samples, language)).trim();
      return text.isEmpty ? null : text;
    } finally {
      timer.cancel();
      await listening.cancel();
      await microphone.stop();
      detector.reset();
    }
  }

  void _end(Float32List? samples) {
    if (_phrase case final phrase? when !phrase.isCompleted) phrase.complete(samples);
  }

  @override
  Future<void> cancel() async => _end(null);

  /// Little-endian 16-bit PCM as samples from -1 to 1.
  static Iterable<double> _samples(Uint8List bytes) sync* {
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      yield data.getInt16(i, Endian.little) / 32768;
    }
  }
}
