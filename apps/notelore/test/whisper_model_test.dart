import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notelore/src/whisper_model.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('notelore_model_'));
  tearDown(() => dir.deleteSync(recursive: true));

  ModelFile file(String name, String text) => ModelFile(
    name,
    'https://models.test/$name',
    sha256.convert(utf8.encode(text)).toString(),
    utf8.encode(text).length,
  );

  final files = [file('encoder.onnx', 'encoder bytes'), file('tokens.txt', 'a 1\nb 2\n')];

  http.Client serving(Map<String, String> pages, {List<String>? asked}) =>
      MockClient.streaming((request, _) async {
        asked?.add(request.url.pathSegments.last);
        final page = pages[request.url.pathSegments.last];
        if (page == null) return http.StreamedResponse(const Stream.empty(), 404);
        // In two chunks, as a download arrives.
        final bytes = utf8.encode(page);
        final half = bytes.length ~/ 2;
        return http.StreamedResponse(
          Stream.fromIterable([bytes.sublist(0, half), bytes.sublist(half)]),
          200,
        );
      });

  test('downloads every file, checked, with progress; then ready', () async {
    final model = WhisperModel(dir.path, files: files);
    expect(model.ready, isFalse);
    final progress = <double>[];
    await model.download(
      client: serving({'encoder.onnx': 'encoder bytes', 'tokens.txt': 'a 1\nb 2\n'}),
      onProgress: progress.add,
    );
    expect(model.ready, isTrue);
    expect(File(p.join(dir.path, 'tokens.txt')).readAsStringSync(), 'a 1\nb 2\n');
    expect(progress.last, 1.0);
    expect(progress, orderedEquals([...progress]..sort()));
    expect(model.path('tokens.txt'), p.join(dir.path, 'tokens.txt'));
    expect(model.bytes, files.fold<int>(0, (sum, f) => sum + f.size));
  });

  test('files already there are not downloaded again', () async {
    final model = WhisperModel(dir.path, files: files);
    File(p.join(dir.path, 'encoder.onnx')).writeAsStringSync('encoder bytes');
    final asked = <String>[];
    await model.download(
      client: serving({'tokens.txt': 'a 1\nb 2\n'}, asked: asked),
      onProgress: (_) {},
    );
    expect(asked, ['tokens.txt']);
    expect(model.ready, isTrue);
  });

  test('a corrupt or failed download keeps nothing and says why', () async {
    final model = WhisperModel(dir.path, files: files);
    await expectLater(
      model.download(
        client: serving({'encoder.onnx': 'tampered bytes', 'tokens.txt': 'a 1\nb 2\n'}),
        onProgress: (_) {},
      ),
      throwsA(isA<ModelDownloadFailed>().having((e) => '$e', 'text', contains('encoder.onnx'))),
    );
    expect(File(p.join(dir.path, 'encoder.onnx')).existsSync(), isFalse);
    expect(dir.listSync().where((f) => f.path.endsWith('.part')), isEmpty);
    await expectLater(
      model.download(client: serving({}), onProgress: (_) {}),
      throwsA(isA<ModelDownloadFailed>().having((e) => '$e', 'text', contains('404'))),
    );
    expect(model.ready, isFalse);
  });

  /// Serves [pages] and honours a Range header with 206, as Hugging Face does.
  http.Client resuming(Map<String, String> pages, List<String?> ranges) =>
      MockClient.streaming((request, _) async {
        ranges.add(request.headers['range']);
        final bytes = utf8.encode(pages[request.url.pathSegments.last]!);
        if (request.headers['range'] case final range?) {
          final from = int.parse(range.substring('bytes='.length, range.length - 1));
          return http.StreamedResponse(
            Stream.value(bytes.sublist(from)),
            206,
            headers: {'content-range': 'bytes $from-${bytes.length - 1}/${bytes.length}'},
          );
        }
        return http.StreamedResponse(Stream.value(bytes), 200);
      });

  test('a download cut off midway keeps what arrived, then resumes from there', () async {
    final model = WhisperModel(dir.path, files: files);
    final cut = MockClient.streaming((request, _) async {
      final bytes = utf8.encode('encoder bytes');
      Stream<List<int>> broken() async* {
        yield bytes.sublist(0, 6);
        throw const SocketException('connection reset');
      }

      return http.StreamedResponse(broken(), 200);
    });
    await expectLater(
      model.download(client: cut, onProgress: (_) {}),
      throwsA(isA<ModelDownloadFailed>().having((e) => '$e', 'text', contains('connection reset'))),
    );
    expect(File(p.join(dir.path, 'encoder.onnx.part')).readAsStringSync(), 'encode');

    final ranges = <String?>[];
    final progress = <double>[];
    await model.download(
      client: resuming({'encoder.onnx': 'encoder bytes', 'tokens.txt': 'a 1\nb 2\n'}, ranges),
      onProgress: progress.add,
    );
    expect(ranges, ['bytes=6-', null]); // the rest of the encoder, then the tokens whole
    expect(model.ready, isTrue);
    expect(progress.first, greaterThan(0)); // what was kept counts from the start
  });

  test('a server that ignores the range sends it all again, and that is fine', () async {
    final model = WhisperModel(dir.path, files: files);
    File(p.join(dir.path, 'encoder.onnx.part')).writeAsStringSync('encode');
    await model.download(
      client: serving({'encoder.onnx': 'encoder bytes', 'tokens.txt': 'a 1\nb 2\n'}),
      onProgress: (_) {},
    );
    expect(model.ready, isTrue);
    // A part longer than the file is not resumed but started over.
    final other = Directory(p.join(dir.path, 'other'));
    File(p.join(other.path, 'encoder.onnx.part'))
      ..createSync(recursive: true)
      ..writeAsStringSync('far too many bytes for this file');
    final ranges = <String?>[];
    await WhisperModel(other.path, files: files).download(
      client: resuming({'encoder.onnx': 'encoder bytes', 'tokens.txt': 'a 1\nb 2\n'}, ranges),
      onProgress: (_) {},
    );
    expect(ranges, [null, null]);
  });

  test('a 206 for a different range is not appended: the file starts over', () async {
    final model = WhisperModel(dir.path, files: files);
    File(p.join(dir.path, 'encoder.onnx.part')).writeAsStringSync('encode');
    var asked = 0;
    final odd = MockClient.streaming((request, _) async {
      asked++;
      final bytes = utf8.encode(
        request.url.pathSegments.last == 'tokens.txt' ? 'a 1\nb 2\n' : 'encoder bytes',
      );
      if (request.headers['range'] != null) {
        // A proxy that answers 206 from the start of the file.
        return http.StreamedResponse(
          Stream.value(bytes),
          206,
          headers: {'content-range': 'bytes 0-12/13'},
        );
      }
      return http.StreamedResponse(Stream.value(bytes), 200);
    });
    await model.download(client: odd, onProgress: (_) {});
    expect(model.ready, isTrue);
    expect(asked, 3); // the odd answer, the whole encoder again, the tokens
  });

  test('a range the server refuses (416) starts the file over, not fails forever', () async {
    final model = WhisperModel(dir.path, files: files);
    File(p.join(dir.path, 'encoder.onnx.part')).writeAsStringSync('stale');
    final refusing = MockClient.streaming((request, _) async {
      if (request.headers['range'] != null) {
        return http.StreamedResponse(const Stream.empty(), 416);
      }
      final name = request.url.pathSegments.last;
      return http.StreamedResponse(
        Stream.value(utf8.encode(name == 'tokens.txt' ? 'a 1\nb 2\n' : 'encoder bytes')),
        200,
      );
    });
    await model.download(client: refusing, onProgress: (_) {});
    expect(model.ready, isTrue);
  });

  test('the real model: Whisper small int8 and the Silero VAD, with checksums', () {
    expect(whisperSmall.map((f) => f.name), [
      'small-encoder.int8.onnx',
      'small-decoder.int8.onnx',
      'small-tokens.txt',
      'silero_vad.onnx',
    ]);
    for (final f in whisperSmall) {
      expect(f.url, startsWith('https://'));
      expect(f.sha256, hasLength(64));
      expect(f.size, greaterThan(0));
    }
    expect(WhisperModel(dir.path).files, whisperSmall);
  });
}
