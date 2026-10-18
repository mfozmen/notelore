/// An attached audio file as text (#285): told apart by its first bytes,
/// decoded to 16 kHz mono (WAV here; other formats by the platform), and
/// heard by Whisper on the device in 30-second parts. Nothing is guessed: no
/// words heard is no text.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'whisper_speech.dart';

/// Whisper's rate, and how much of it one call hears.
const _rate = 16000;
const _part = 30 * _rate;

bool _starts(List<int> bytes, String text, [int at = 0]) =>
    bytes.length >= at + text.length &&
    latin1.decode(bytes.sublist(at, at + text.length), allowInvalid: true) == text;

/// A RIFF WAVE file.
bool isWav(List<int> bytes) => _starts(bytes, 'RIFF') && _starts(bytes, 'WAVE', 8);

/// WAV, M4A/AAC, MP3, Ogg (Vorbis, Opus) or FLAC, by their first bytes.
bool isAudio(List<int> bytes) =>
    isWav(bytes) ||
    _starts(bytes, 'ftypM4A', 4) ||
    _starts(bytes, 'ftypM4B', 4) ||
    _starts(bytes, 'ID3') ||
    // An MP3 frame (MPEG layer III); a looser check would take a UTF-16 text's BOM.
    (bytes.length > 1 &&
        bytes[0] == 0xFF &&
        const {0xFB, 0xFA, 0xF3, 0xF2, 0xE3, 0xE2}.contains(bytes[1])) ||
    _starts(bytes, 'OggS') ||
    _starts(bytes, 'fLaC');

/// A WAV's sound as 16 kHz mono samples (-1..1); null when it is not a PCM
/// (16-bit) or float (32-bit) WAV this can read.
Float32List? wavSamples(Uint8List bytes) {
  if (!isWav(bytes)) return null;
  final data = ByteData.sublistView(bytes);
  int? format, channels, rate, bits;
  ByteData? sound;
  for (var at = 12; at + 8 <= bytes.length;) {
    final size = data.getUint32(at + 4, Endian.little);
    final body = at + 8;
    if (_starts(bytes, 'fmt ', at) && body + 16 <= bytes.length) {
      format = data.getUint16(body, Endian.little);
      channels = data.getUint16(body + 2, Endian.little);
      rate = data.getUint32(body + 4, Endian.little);
      bits = data.getUint16(body + 14, Endian.little);
    } else if (_starts(bytes, 'data', at)) {
      final end = body + size > bytes.length ? bytes.length : body + size;
      sound = ByteData.sublistView(bytes, body, end);
    }
    at = body + size + size % 2;
  }
  final pcm = format == 1 && bits == 16;
  final float = format == 3 && bits == 32;
  if (sound == null || channels == null || channels == 0 || rate == null || !(pcm || float)) {
    return null;
  }
  final width = bits! ~/ 8 * channels;
  final frames = sound.lengthInBytes ~/ width;
  final mono = Float32List(frames);
  for (var f = 0; f < frames; f++) {
    var sum = 0.0;
    for (var c = 0; c < channels; c++) {
      final at = f * width + c * bits ~/ 8;
      sum += pcm ? sound.getInt16(at, Endian.little) / 32768 : sound.getFloat32(at, Endian.little);
    }
    mono[f] = sum / channels;
  }
  return resample(mono, rate);
}

/// [samples] at [rate] as 16 kHz, by straight lines between samples: enough
/// for speech.
Float32List resample(Float32List samples, int rate) {
  if (rate == _rate) return samples;
  final out = Float32List((samples.length * _rate / rate).round());
  for (var i = 0; i < out.length; i++) {
    final at = i * rate / _rate;
    final low = at.floor();
    final high = low + 1 < samples.length ? low + 1 : low;
    out[i] = samples[low] + (samples[high] - samples[low]) * (at - low);
  }
  return out;
}

/// What Whisper hears in [samples], 30 seconds at a time, without its notes on
/// sounds; null when no words are heard.
Future<String?> transcribeSamples(
  Float32List samples,
  Transcriber transcriber,
  String language,
) async {
  final parts = <String>[];
  for (var at = 0; at < samples.length; at += _part) {
    final end = at + _part < samples.length ? at + _part : samples.length;
    final heard = withoutSoundNotes(
      await transcriber.transcribe(Float32List.sublistView(samples, at, end), language),
    );
    if (heard != null) parts.add(heard);
  }
  return parts.isEmpty ? null : parts.join(' ');
}

/// Whisper is not on this device yet: an audio file cannot be heard.
class AudioUnavailable implements Exception {
  const AudioUnavailable();
}

/// An audio format this device cannot open.
class AudioUnreadable implements Exception {
  const AudioUnreadable();
}
