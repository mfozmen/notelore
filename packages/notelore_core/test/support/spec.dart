import 'dart:io';

/// The shared note fixtures in `spec/fixtures/notes`, found from any working directory
/// inside the repository: the contract both the Dart and the Python implementation meet.
Directory specFixtures() {
  var dir = Directory.current.absolute;
  while (true) {
    final candidate = Directory('${dir.path}/spec/fixtures/notes');
    if (candidate.existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('spec/fixtures/notes not found above ${Directory.current.path}');
    }
    dir = parent;
  }
}

/// Fixture files by name, sorted, as raw bytes.
Map<String, List<int>> fixtureBytes() {
  final files =
      specFixtures().listSync().whereType<File>().where((f) => f.path.endsWith('.md')).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return {for (final f in files) f.uri.pathSegments.last: f.readAsBytesSync()};
}
