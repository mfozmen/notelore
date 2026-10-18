/// Speech recognition inside the app, push to talk: the microphone records
/// while the button is held, then Whisper writes down the whole recording.
/// Offline and free, the same in every language and on every platform (the
/// device recognizers differ: Windows' cannot do Turkish at all).
library;

import 'dart:async';
import 'dart:typed_data';

import 'voice.dart';

/// A microphone the device lists: its platform id and its name.
typedef MicrophoneChoice = ({String id, String label});

/// Whisper's notes on sounds, not words: `[MUSIC PLAYING]`, `[BLANK_AUDIO]`,
/// `(laughs)`, `*sighs*`, `♪`. It writes them for noise or silence (#163). An
/// asterisk note hugs its letters; a spoken "2 * 3" has spaces and stays.
final _soundNotes = RegExp(
  r'\[[^\]]*\]|\([^)]*\)|\*\p{L}(?:[\p{L} ]{0,30}\p{L})?\*|♪',
  unicode: true,
);
final _letter = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// What was said in [text], without Whisper's notes on sounds; null when
/// nothing was, so noise is never sent as a message.
String? withoutSoundNotes(String text) {
  final said = text.replaceAll(_soundNotes, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return _letter.hasMatch(said) ? said : null;
}

/// 16 kHz, mono, 16-bit PCM from the microphone.
abstract interface class Microphone {
  /// Throws [VoiceUnavailable] without a microphone or its permission.
  Future<Stream<Uint8List>> start();

  Future<void> stop();
}

/// Turns a recording into text.
abstract interface class Transcriber {
  Future<String> transcribe(Float32List samples, String language);
}

class WhisperSpeech implements Speech {
  WhisperSpeech({
    required this.microphone,
    required this.transcriber,
    this.longest = const Duration(minutes: 2),
  });

  final Microphone microphone;
  final Transcriber transcriber;

  /// A button held (or stuck) this long ends the recording by itself.
  final Duration longest;

  /// Completes true to keep the recording ([finish]), false to drop it ([cancel]).
  Completer<bool>? _done;

  @override
  Future<String?> listen(String language) async {
    final done = _done = Completer<bool>();
    final audio = await microphone.start();
    final heard = <double>[];
    final timer = Timer(longest, () => _end(keep: true));
    final listening = audio.listen(
      (bytes) => heard.addAll(_samples(bytes)),
      onError: (Object error) {
        if (!done.isCompleted) done.completeError(ListenFailed('$error'));
      },
    );
    try {
      // shortcut: what is still on its way when the button is let go (a few
      // milliseconds) is not waited for; wait for the stream's end if words get cut.
      if (!await done.future || heard.isEmpty) return null;
      return withoutSoundNotes(await transcriber.transcribe(Float32List.fromList(heard), language));
    } finally {
      timer.cancel();
      await listening.cancel();
      await microphone.stop();
    }
  }

  void _end({required bool keep}) {
    if (_done case final done? when !done.isCompleted) done.complete(keep);
  }

  @override
  Future<void> finish() async => _end(keep: true);

  @override
  Future<void> cancel() async => _end(keep: false);

  /// Little-endian 16-bit PCM as samples from -1 to 1.
  static Iterable<double> _samples(Uint8List bytes) sync* {
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      yield data.getInt16(i, Endian.little) / 32768;
    }
  }
}
