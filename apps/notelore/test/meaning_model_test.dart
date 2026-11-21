import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/meaning_model.dart';
import 'package:path/path.dart' as p;

void main() {
  test('the e5 files everywhere; onnxruntime as well on macOS (#929)', () {
    expect(meaningFilesFor(macOS: false).map((f) => f.name), [
      'model_quantized.onnx',
      'tokenizer.json',
    ]);
    expect(meaningFilesFor(macOS: true).map((f) => f.name), [
      'model_quantized.onnx',
      'tokenizer.json',
      ortWheel,
    ]);
    for (final f in meaningFilesFor(macOS: true)) {
      expect(f.url, startsWith('https://'));
      expect(f.sha256, hasLength(64));
    }
  });

  test('onnxruntime comes out of its downloaded wheel once; none without one', () {
    final dir = Directory.systemTemp.createTempSync('meaning_').path;
    addTearDown(() => Directory(dir).deleteSync(recursive: true));
    expect(ortLibrary(dir), isNull);
    final wheel = Archive()
      ..add(ArchiveFile.bytes('onnxruntime/__init__.py', [1]))
      ..add(ArchiveFile.bytes('onnxruntime/capi/libonnxruntime.1.22.1.dylib', [7, 7, 7]));
    File(p.join(dir, ortWheel)).writeAsBytesSync(ZipEncoder().encode(wheel));
    final library = ortLibrary(dir)!;
    expect(File(library).readAsBytesSync(), [7, 7, 7]);
    // Taken out once: a later start uses it as it is.
    File(library).writeAsBytesSync([1]);
    expect(File(ortLibrary(dir)!).readAsBytesSync(), [1]);
  });

  test('a wheel without the library gives none', () {
    final dir = Directory.systemTemp.createTempSync('meaning_').path;
    addTearDown(() => Directory(dir).deleteSync(recursive: true));
    final wheel = Archive()..add(ArchiveFile.bytes('onnxruntime/__init__.py', [1]));
    File(p.join(dir, ortWheel)).writeAsBytesSync(ZipEncoder().encode(wheel));
    expect(ortLibrary(dir), isNull);
  });
}
