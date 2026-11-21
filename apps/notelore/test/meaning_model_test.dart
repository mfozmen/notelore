import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/meaning_model.dart';
import 'package:notelore/src/whisper_model.dart' show ModelFile;
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

  test('each file must be the pinned one; one that is not goes, to be downloaded again', () {
    final dir = Directory.systemTemp.createTempSync('meaning_').path;
    addTearDown(() => Directory(dir).deleteSync(recursive: true));
    final good = ModelFile('a', 'https://x/a', '${sha256.convert([1, 2])}', 2);
    final swapped = ModelFile('b', 'https://x/b', '${sha256.convert([3, 4])}', 2);
    File(p.join(dir, 'a')).writeAsBytesSync([1, 2]);
    expect(intact(dir, [good]), isTrue);
    expect(intact(dir, [good, swapped]), isFalse); // missing
    File(p.join(dir, 'b')).writeAsBytesSync([9, 9]); // same size, other bytes
    expect(intact(dir, [good, swapped]), isFalse);
    expect(File(p.join(dir, 'b')).existsSync(), isFalse);
    expect(File(p.join(dir, 'a')).existsSync(), isTrue);
  });

  test('onnxruntime comes out of its downloaded wheel, checked before every load', () {
    final dir = Directory.systemTemp.createTempSync('meaning_').path;
    addTearDown(() => Directory(dir).deleteSync(recursive: true));
    final pinned = '${sha256.convert([7, 7, 7])}';
    expect(ortLibrary(dir, sha: pinned), isNull);
    final wheel = Archive()
      ..add(ArchiveFile.bytes('onnxruntime/__init__.py', [1]))
      ..add(ArchiveFile.bytes('onnxruntime/capi/libonnxruntime.1.22.1.dylib', [7, 7, 7]));
    File(p.join(dir, ortWheel)).writeAsBytesSync(ZipEncoder().encode(wheel));
    final library = ortLibrary(dir, sha: pinned)!;
    expect(File(library).readAsBytesSync(), [7, 7, 7]);
    expect(ortLibrary(dir, sha: pinned), library);
    // Swapped since: never loaded, taken out of the wheel again.
    File(library).writeAsBytesSync([6, 6, 6]);
    expect(File(ortLibrary(dir, sha: pinned)!).readAsBytesSync(), [7, 7, 7]);
    // A wheel whose library is not the pinned one gives none.
    File(library).deleteSync();
    expect(ortLibrary(dir), isNull);
    expect(File(library).existsSync(), isFalse);
  });

  test('a wheel without the library gives none', () {
    final dir = Directory.systemTemp.createTempSync('meaning_').path;
    addTearDown(() => Directory(dir).deleteSync(recursive: true));
    final wheel = Archive()..add(ArchiveFile.bytes('onnxruntime/__init__.py', [1]));
    File(p.join(dir, ortWheel)).writeAsBytesSync(ZipEncoder().encode(wheel));
    expect(ortLibrary(dir), isNull);
  });
}
