/// The signed manifest of a changed-files Windows update (#584).
library;

import 'dart:convert';

final _sha256 = RegExp(r'^[0-9a-f]{64}$');

/// Whether [path] is a safe relative path inside an app folder: no drive, no
/// backslashes, no `..`, no empty segment.
bool isSafeUpdatePath(String path) {
  if (path.isEmpty ||
      path.startsWith('/') ||
      path.startsWith(r'\') ||
      path.contains(r'\') ||
      path.contains(':')) {
    return false;
  }
  return path.split('/').every((part) => part.isNotEmpty && part != '.' && part != '..');
}

/// A release's changed-files manifest. The release key signs the JSON bytes;
/// [files] are the new files and their SHA-256, and [archive] carries them.
final class DeltaManifest {
  const DeltaManifest({
    required this.version,
    required this.from,
    required this.system,
    required this.archive,
    required this.archiveSha256,
    required this.files,
  });

  final String version;
  final String from;
  final String system;
  final String archive;
  final String archiveSha256;
  final Map<String, String> files;

  /// Parses [text] for [current] on [system]. Throws [FormatException] for
  /// anything that is not a manifest for this exact upgrade.
  factory DeltaManifest.parse(String text, {required String current, required String system}) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const FormatException('delta manifest is not JSON');
    }
    if (json is! Map<String, Object?>) {
      throw const FormatException('delta manifest is not an object');
    }
    final map = json;
    String field(String name) {
      final value = map[name];
      if (value is! String || value.isEmpty) {
        throw FormatException("delta manifest has no '$name'");
      }
      return value;
    }

    final version = field('version');
    final from = field('from');
    final manifestSystem = field('system');
    final archive = field('archive');
    final archiveSha = field('archive_sha256');
    if (from != current) {
      throw FormatException("delta manifest is from '$from', not '$current'");
    }
    if (manifestSystem != system) {
      throw FormatException("delta manifest is for '$manifestSystem', not '$system'");
    }
    if (!isSafeUpdatePath(archive) || archive.contains('/') || !archive.endsWith('.zip')) {
      throw FormatException("delta archive name '$archive' is not a plain zip name");
    }
    if (!_sha256.hasMatch(archiveSha)) {
      throw const FormatException('delta archive hash is not SHA-256');
    }
    final rawFiles = map['files'];
    if (rawFiles is! Map<String, Object?> || rawFiles.isEmpty) {
      throw const FormatException('delta manifest lists no files');
    }
    final files = <String, String>{};
    for (final MapEntry(key: path, value: hash) in rawFiles.entries) {
      if (!isSafeUpdatePath(path) || path.toLowerCase() == 'notelore-updater.exe') {
        throw FormatException("delta manifest path '$path' is not safe");
      }
      if (hash is! String || !_sha256.hasMatch(hash)) {
        throw FormatException("delta manifest hash for '$path' is not SHA-256");
      }
      files[path] = hash;
    }
    return DeltaManifest(
      version: version,
      from: from,
      system: manifestSystem,
      archive: archive,
      archiveSha256: archiveSha,
      files: files,
    );
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'from': from,
    'system': system,
    'archive': archive,
    'archive_sha256': archiveSha256,
    'files': files,
  };
}

/// The release asset name of the manifest from [from] to [version].
String deltaName(String version, String system, String from) =>
    'notelore-app-$version-$system-delta-$from.json';
