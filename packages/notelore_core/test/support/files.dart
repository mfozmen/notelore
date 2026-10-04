import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A fresh temp directory, deleted after the test.
String tempDir() {
  final dir = Directory.systemTemp.createTempSync('notelore_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir.path;
}

/// Copies the tree under [source] to [target], keeping modification times.
void copyTree(String source, String target) {
  for (final entity in Directory(source).listSync(recursive: true)) {
    final to = p.join(target, p.relative(entity.path, from: source));
    if (entity is File) {
      File(to).parent.createSync(recursive: true);
      entity.copySync(to);
      File(to).setLastModifiedSync(entity.lastModifiedSync());
    }
  }
}

String read(String path) => File(path).readAsStringSync();
