/// The on-device speech model: Whisper small (int8) for transcription and the
/// Silero voice-activity model that finds where a phrase ends. Downloaded once
/// on request (not bundled), each file checked against its SHA-256.
library;

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

final class ModelFile {
  const ModelFile(this.name, this.url, this.sha256, this.size);

  final String name;
  final String url;
  final String sha256;
  final int size;
}

const _whisper =
    'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-small/resolve/8f3c18b358db4d1f2fc1eae49d75cd20989e4309';

/// sherpa-onnx's export of OpenAI Whisper small (MIT), and Silero VAD (MIT).
const whisperSmall = [
  ModelFile(
    'small-encoder.int8.onnx',
    '$_whisper/small-encoder.int8.onnx',
    '4cbe7b22fa9026b843b60a68640c747de05bafb1a11b57edc0e66c232d9f33a9',
    112442483,
  ),
  ModelFile(
    'small-decoder.int8.onnx',
    '$_whisper/small-decoder.int8.onnx',
    'acad50b5c782696e91b55914cc5ab4f756f1532f76e22aa6fc615f39fb69a8ee',
    262226114,
  ),
  ModelFile(
    'small-tokens.txt',
    '$_whisper/small-tokens.txt',
    'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126',
    816730,
  ),
  ModelFile(
    'silero_vad.onnx',
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx',
    '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6',
    643854,
  ),
];

/// A download did not complete or did not match its checksum; nothing is kept.
class ModelDownloadFailed implements Exception {
  const ModelDownloadFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

class WhisperModel {
  WhisperModel(this.dir, {this.files = whisperSmall});

  /// Where the model files live (device state, never the notes folder).
  final String dir;
  final List<ModelFile> files;

  String path(String name) => p.join(dir, name);

  /// All of it, in bytes: what a download costs.
  int get bytes => files.fold(0, (sum, f) => sum + f.size);

  bool _present(ModelFile file) {
    final f = File(path(file.name));
    return f.existsSync() && f.lengthSync() == file.size;
  }

  /// Every file is on the device.
  bool get ready => files.every(_present);

  /// Downloads what is missing, reporting progress from 0 to 1. Each file is
  /// written as `.part`, checked, then renamed. Throws [ModelDownloadFailed].
  Future<void> download({
    required http.Client client,
    required void Function(double done) onProgress,
  }) async {
    Directory(dir).createSync(recursive: true);
    var done = 0;
    for (final file in files) {
      if (_present(file)) {
        done += file.size;
        onProgress(done / bytes);
        continue;
      }
      final answer = await client.send(http.Request('GET', Uri.parse(file.url)));
      if (answer.statusCode != 200) {
        throw ModelDownloadFailed('${file.name}: HTTP ${answer.statusCode}');
      }
      // Opened only once the server answers: a refused download leaves no file.
      final part = File('${path(file.name)}.part');
      final sink = part.openWrite();
      final hash = _Digest();
      final hashing = sha256.startChunkedConversion(hash);
      try {
        await for (final chunk in answer.stream) {
          sink.add(chunk);
          hashing.add(chunk);
          done += chunk.length;
          onProgress(done / bytes);
        }
        hashing.close();
        await sink.close();
        if ('${hash.value}' != file.sha256) {
          throw ModelDownloadFailed('${file.name}: the download does not match its checksum');
        }
        part.renameSync(path(file.name));
      } catch (_) {
        await sink.close();
        if (part.existsSync()) part.deleteSync();
        rethrow;
      }
    }
    onProgress(1);
  }
}

class _Digest implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
