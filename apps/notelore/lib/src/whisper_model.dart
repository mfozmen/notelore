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

/// sherpa-onnx's export of OpenAI Whisper small (MIT).
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
  /// written as `.part`, checked, then renamed. A connection lost midway keeps
  /// the `.part`, and the next download asks only for the rest (a Range
  /// request); a server that ignores it sends the whole file again. Throws
  /// [ModelDownloadFailed].
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
      final part = File('${path(file.name)}.part');
      final (answer, kept) = await _request(client, file, part);
      done = await _save(file, part, answer, kept: kept, done: done, onProgress: onProgress);
    }
    onProgress(1);
  }

  /// The server's answer for [file], and how much of [part] it goes on from:
  /// the rest when the server sends exactly that, else the whole file (0).
  Future<(http.StreamedResponse, int)> _request(
    http.Client client,
    ModelFile file,
    File part,
  ) async {
    var kept = part.existsSync() ? part.lengthSync() : 0;
    if (kept >= file.size) kept = 0; // not a beginning of this file: start over
    var answer = await client.send(_get(file.url, from: kept));
    if (kept > 0) {
      // Appended only when the server sends the rest from exactly there; any
      // other answer to the range (a refusal, another range) fetches it whole.
      if (answer.statusCode == 206 &&
          '${answer.headers['content-range']}'.startsWith('bytes $kept-')) {
        return (answer, kept);
      }
      if (answer.statusCode != 200) {
        await answer.stream.drain<void>();
        answer = await client.send(_get(file.url));
      }
    }
    if (answer.statusCode != 200) {
      throw ModelDownloadFailed('${file.name}: HTTP ${answer.statusCode}');
    }
    return (answer, 0);
  }

  /// Writes [answer] to [part] after its first [kept] bytes, checks the whole
  /// against [file]'s checksum and puts it in place. Returns the bytes [done].
  Future<int> _save(
    ModelFile file,
    File part,
    http.StreamedResponse answer, {
    required int kept,
    required int done,
    required void Function(double done) onProgress,
  }) async {
    final hash = _Digest();
    final hashing = sha256.startChunkedConversion(hash);
    if (kept > 0) {
      await part.openRead().forEach(hashing.add); // what is kept counts toward the checksum
      done += kept;
      onProgress(done / bytes);
    }
    // Opened only once the server answers: a refused download leaves no file.
    final sink = part.openWrite(mode: kept > 0 ? FileMode.append : FileMode.write);
    var written = kept;
    try {
      await for (final chunk in answer.stream) {
        // More than the file is never written: a wrong or hostile server must
        // not fill the disk the notes are on.
        if ((written += chunk.length) > file.size) {
          await sink.close();
          part.deleteSync();
          throw ModelDownloadFailed('${file.name}: the download is larger than the file');
        }
        sink.add(chunk);
        hashing.add(chunk);
        done += chunk.length;
        onProgress(done / bytes);
      }
    } on ModelDownloadFailed {
      rethrow;
    } on Object catch (error) {
      // What arrived stays, for the next try to go on from; the download's
      // error says more than one from closing the file.
      await sink.close().then<void>((_) {}, onError: (Object _) {});
      throw ModelDownloadFailed('${file.name}: $error');
    }
    hashing.close();
    await sink.close();
    if ('${hash.value}' != file.sha256) {
      part.deleteSync();
      throw ModelDownloadFailed('${file.name}: the download does not match its checksum');
    }
    part.renameSync(path(file.name));
    return done;
  }
}

/// A GET for [url], from byte [from] on when it is not 0.
http.Request _get(String url, {int from = 0}) {
  final request = http.Request('GET', Uri.parse(url));
  if (from > 0) request.headers['range'] = 'bytes=$from-';
  return request;
}

class _Digest implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
