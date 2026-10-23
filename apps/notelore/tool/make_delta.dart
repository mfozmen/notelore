// Builds the signed-manifest changed-files update for Windows (#584):
// compares an installed previous app with the new build and writes only the
// files that changed, plus the manifest the app verifies.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:notelore/src/update_delta.dart';
import 'package:path/path.dart' as p;

const _helper = 'notelore-updater.exe';

Map<String, String> _tree(String root) {
  final folder = Directory(root);
  if (!folder.existsSync()) throw StateError('no app folder at $root');
  final files = <String, String>{};
  for (final file in folder.listSync(recursive: true).whereType<File>()) {
    final path = p.relative(file.path, from: root).replaceAll(r'\', '/');
    final name = p.basename(path).toLowerCase();
    if ((name.startsWith('unins') && name.endsWith('.exe')) ||
        name.endsWith('.pdb') ||
        name.endsWith('.old')) {
      continue;
    }
    files[path] = sha256.convert(file.readAsBytesSync()).toString();
  }
  return files;
}

/// Writes a delta from [old] to [newRoot] into [out], or returns null when a
/// delta is not safe (an old app has no helper, or nothing else changed).
Future<({DeltaManifest manifest, File archive})?> makeDelta({
  required String old,
  required String newRoot,
  required String version,
  required String from,
  required String out,
}) async {
  final before = _tree(old);
  final after = _tree(newRoot);
  final oldHelper = before[_helper];
  final newHelper = after[_helper];
  // The helper cannot replace itself while it runs; its job format is stable,
  // so a changed helper stays behind until a full setup. An old app without
  // one cannot apply a delta at all.
  if (newHelper == null || oldHelper == null) return null;
  final changed = [
    for (final MapEntry(key: path, value: hash) in after.entries)
      if (path != _helper && before[path] != hash) path,
  ]..sort();
  if (changed.isEmpty) return null;

  final zip = Archive();
  for (final path in changed) {
    final bytes = File(p.joinAll([newRoot, ...path.split('/')])).readAsBytesSync();
    zip.addFile(ArchiveFile(path, bytes.length, bytes));
  }
  final archive = ZipEncoder().encode(zip);
  final archiveName = 'notelore-app-$version-windows-x64-delta-$from.zip';
  final folder = Directory(out)..createSync(recursive: true);
  final archiveFile = File(p.join(folder.path, archiveName))..writeAsBytesSync(archive);
  final manifest = DeltaManifest(
    version: version,
    from: from,
    system: 'windows',
    archive: archiveName,
    archiveSha256: sha256.convert(archive).toString(),
    files: {for (final path in changed) path: after[path]!},
  );
  File(p.join(folder.path, deltaName(version, 'windows-x64', from)))
      .writeAsStringSync(jsonEncode(manifest.toJson()));
  return (manifest: manifest, archive: archiveFile);
}

Future<void> main(List<String> args) async {
  final options = {
    for (final arg in args)
      if (arg.startsWith('--') && arg.contains('='))
        arg.substring(2, arg.indexOf('=')): arg.substring(arg.indexOf('=') + 1),
  };
  final old = options['old'];
  final next = options['new'];
  final version = options['version'];
  final from = options['from'];
  final out = options['out'];
  if (old == null || next == null || version == null || from == null || out == null) {
    stderr.writeln(
      'usage: make_delta --old=<dir> --new=<dir> --version=<v> --from=<v> --out=<dir>',
    );
    exit(64);
  }
  final delta = await makeDelta(old: old, newRoot: next, version: version, from: from, out: out);
  if (delta == null) {
    stdout.writeln('no delta for $from -> $version');
    return;
  }
  stdout.writeln('${delta.manifest.files.length} files -> ${delta.archive.path}');
}
