/// The platform's audio decoder for an attached file that is not WAV (#285):
/// Android's MediaCodec through MainActivity, 16 kHz mono 16-bit PCM back.
/// Native code `flutter test` cannot run; the logic around it is in
/// audio_file.dart, tested.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'audio_file.dart' show resample;

// coverage:ignore-start
const _channel = MethodChannel('io.github.mfozmen.notelore/audio');

/// [bytes] as 16 kHz mono samples, or null where this platform cannot open them.
Future<Float32List?> nativeDecodeAudio(Uint8List bytes) async {
  // shortcut: the desktop opens WAV only; add a decoder there if asked.
  if (!Platform.isAndroid) return null;
  try {
    final decoded = await _channel.invokeMapMethod<String, Object?>('decode', bytes);
    final pcm = decoded?['pcm'] as Uint8List?;
    final rate = decoded?['rate'] as int?;
    if (pcm == null || rate == null) return null;
    final data = ByteData.sublistView(pcm);
    final samples = Float32List(pcm.length ~/ 2);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = data.getInt16(i * 2, Endian.little) / 32768;
    }
    return resample(samples, rate);
  } on PlatformException {
    return null; // the codec could not open it
  }
}
// coverage:ignore-end
