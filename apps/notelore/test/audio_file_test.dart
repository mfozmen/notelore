import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/audio_file.dart';
import 'package:notelore/src/whisper_speech.dart';

/// A RIFF WAVE file of [samples] (each -1..1) at [rate], [channels] interleaved,
/// 16-bit PCM or 32-bit float.
Uint8List wav(List<double> samples, {int rate = 16000, int channels = 1, bool float = false}) {
  final bytesPer = float ? 4 : 2;
  final data = ByteData(samples.length * bytesPer);
  for (final (i, s) in samples.indexed) {
    float
        ? data.setFloat32(i * 4, s, Endian.little)
        : data.setInt16(i * 2, (s * 32767).round(), Endian.little);
  }
  final header = ByteData(44)
    ..setUint32(0, 0x46464952, Endian.little) // RIFF
    ..setUint32(4, 36 + data.lengthInBytes, Endian.little)
    ..setUint32(8, 0x45564157, Endian.little) // WAVE
    ..setUint32(12, 0x20746d66, Endian.little) // "fmt "
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, float ? 3 : 1, Endian.little)
    ..setUint16(22, channels, Endian.little)
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * channels * bytesPer, Endian.little)
    ..setUint16(32, channels * bytesPer, Endian.little)
    ..setUint16(34, bytesPer * 8, Endian.little)
    ..setUint32(36, 0x61746164, Endian.little) // data
    ..setUint32(40, data.lengthInBytes, Endian.little);
  return Uint8List.fromList([...header.buffer.asUint8List(), ...data.buffer.asUint8List()]);
}

class _Transcriber implements Transcriber {
  final lengths = <int>[];
  final answers = <String>[];

  @override
  Future<String> transcribe(Float32List samples, String language) async {
    lengths.add(samples.length);
    return answers.isEmpty ? 'part' : answers.removeAt(0);
  }
}

void main() {
  test('audio is told by its first bytes (#285)', () {
    expect(isAudio(wav([0, 0])), isTrue);
    expect(isAudio([0, 0, 0, 0x20, ...'ftypM4A '.codeUnits]), isTrue); // m4a
    expect(isAudio([...'ID3'.codeUnits, 3, 0]), isTrue); // mp3 with a tag
    expect(isAudio([0xFF, 0xFB, 0x90, 0]), isTrue); // mp3 frame
    expect(isAudio([...'OggS'.codeUnits, 0]), isTrue);
    expect(isAudio([...'fLaC'.codeUnits, 0]), isTrue);
    expect(isAudio('hello'.codeUnits), isFalse);
    expect(isAudio([0xFF, 0xFE, 0x41, 0]), isFalse); // a UTF-16 text, not an MP3
    expect(isAudio([0, 0, 0, 0x18, ...'ftypmp42'.codeUnits]), isFalse); // a video
    expect(isWav(wav([0])), isTrue);
    expect(isWav([...'OggS'.codeUnits, 0, 0, 0, 0]), isFalse);
  });

  test('a WAV becomes 16 kHz mono samples, whatever its rate, channels or format', () {
    // One second of stereo at 44.1 kHz: left 0.5, right -0.5, so mono is silence.
    final stereo = wav(
      [
        for (var i = 0; i < 44100; i++) ...[0.5, -0.5],
      ],
      rate: 44100,
      channels: 2,
    );
    final samples = wavSamples(stereo)!;
    expect(samples.length, closeTo(16000, 1));
    expect(samples.every((s) => s.abs() < 1e-3), isTrue);
    final floats = wavSamples(wav(List.filled(8000, 0.25), rate: 8000, float: true))!;
    expect(floats.length, 16000);
    expect(floats[100], closeTo(0.25, 1e-6));
    final mono = wavSamples(wav(List.filled(16000, 0.5)))!;
    expect(mono[10], closeTo(0.5, 1e-3));
    expect(wavSamples(Uint8List.fromList('RIFF....WAVEjunk'.codeUnits)), isNull); // no fmt or data
    expect(wavSamples(Uint8List.fromList('nope'.codeUnits)), isNull);
  });

  test('long audio goes to Whisper in 30 s parts; notes on sounds are dropped', () async {
    final transcriber = _Transcriber()..answers.addAll(['Hello', '[MUSIC]', 'world.']);
    final text = await transcribeSamples(
      Float32List(16000 * 70), // 70 seconds
      transcriber,
      'en',
    );
    expect(transcriber.lengths, [480000, 480000, 160000]);
    expect(text, 'Hello world.');
    final silent = _Transcriber()..answers.add('[BLANK_AUDIO]');
    expect(await transcribeSamples(Float32List(16000), silent, 'en'), isNull);
    expect(await transcribeSamples(Float32List(0), silent, 'en'), isNull);
  });
}
