/// Speech recognition inside the app: the microphone's audio goes through a
/// voice-activity detector until a phrase ends, then Whisper writes it down.
/// Offline and free, the same in every language and on every platform (the
/// device recognizers differ: Windows' cannot do Turkish at all).
library;

import 'dart:async';
import 'dart:math';
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

  /// Someone is talking right now.
  bool get speaking;

  void reset();
}

/// Turns a phrase into text.
abstract interface class Transcriber {
  Future<String> transcribe(Float32List samples, String language);
}

/// Raises a quiet microphone to a level the detector hears (Windows applies no
/// gain of its own): towards half full scale, at most 20 times, never quieter.
/// The level is the recent peak, fading slowly, so words keep one gain.
class AutoGain {
  static const _target = 0.5;
  static const _most = 20.0;
  static const _fade = 0.995; // per 32 ms window: about 4 s to halve

  double _level = 0;

  Float32List apply(Float32List samples) {
    _level = samples.fold(_level * _fade, (level, s) => max(level, s.abs()));
    final gain = _level == 0 ? 1.0 : (_target / _level).clamp(1.0, _most);
    return Float32List.fromList([for (final s in samples) s * gain]);
  }
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
  final _gain = AutoGain();

  @override
  Future<String?> listen(String language) async {
    final phrase = _phrase = Completer<Float32List?>();
    final audio = await microphone.start();
    final pending = <double>[];
    var timer = Timer(silence, () => _end(null));
    final listening = audio.listen(
      (bytes) {
        pending.addAll(_samples(bytes));
        while (pending.length >= detector.window && !phrase.isCompleted) {
          final window = Float32List.fromList(pending.sublist(0, detector.window));
          pending.removeRange(0, detector.window);
          if (detector.accept(_gain.apply(window)) case final done?) _end(done);
          if (detector.speaking) {
            // The timeout is for silence: a long phrase keeps it waiting.
            timer.cancel();
            timer = Timer(silence, () => _end(null));
          }
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
