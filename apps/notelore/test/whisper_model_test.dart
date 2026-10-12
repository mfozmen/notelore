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
