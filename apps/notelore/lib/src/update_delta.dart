/// The signed manifest of a changed-files Windows update (#584).
library;

import 'dart:convert';

final _sha256 = RegExp(r'^[0-9a-f]{64}$');
const _reserved = {
  'con',
  'prn',
  'aux',
  'nul',
  'com1',
  'com2',
  'com3',
  'com4',
  'com5',
  'com6',
  'com7',
  'com8',
  'com9',
  'lpt1',
  'lpt2',
  'lpt3',
  'lpt4',
  'lpt5',
  'lpt6',
  'lpt7',
  'lpt8',
  'lpt9',
};

/// Whether [path] is a safe relative path inside an app folder: no drive, no
/// backslashes, no `..`, no empty segment, no Win32 alias or device name.
bool isSafeUpdatePath(String path) {
  if (path.isEmpty ||
      path.startsWith('/') ||
      path.startsWith(r'\') ||
      path.contains(r'\') ||
      path.contains(':')) {
    return false;
  }
  return path.split('/').every(_safeSegment);
}

bool _safeSegment(String part) {
  if (part.isEmpty || part == '.' || part == '..') return false;
  if (part.endsWith('.') || part.endsWith(' ')) return false;
  return !_reserved.contains(part.split('.').first.toLowerCase());
}

Map<String, Object?> _object(String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    throw const FormatException('delta manifest is not JSON');
  }
  if (json is! Map<String, Object?>) {
    throw const FormatException('delta manifest is not an object');
  }
  return json;
}

String _string(Map<String, Object?> map, String name) {
  final value = map[name];
  if (value is! String || value.isEmpty) {
    throw FormatException("delta manifest has no '$name'");
  }
  return value;
}

Map<String, String> _files(Object? raw) {
  if (raw is! Map<String, Object?> || raw.isEmpty) {
    throw const FormatException('delta manifest lists no files');
  }
  final files = <String, String>{};
  for (final MapEntry(key: path, value: hash) in raw.entries) {
    if (!isSafeUpdatePath(path) || path.toLowerCase() == 'notelore-updater.exe') {
      throw FormatException("delta manifest path '$path' is not safe");
    }
    if (hash is! String || !_sha256.hasMatch(hash)) {
      throw FormatException("delta manifest hash for '$path' is not SHA-256");
    }
    files[path] = hash;
  }
  return files;
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

  /// Parses [text] for the exact [version], [current] and [system] upgrade.
  /// Throws [FormatException] for anything that does not match.
  factory DeltaManifest.parse(
    String text, {
    required String version,
    required String current,
    required String system,
  }) {
    final map = _object(text);
    final from = _string(map, 'from');
    final manifestSystem = _string(map, 'system');
    final archive = _string(map, 'archive');
    final archiveSha = _string(map, 'archive_sha256');
    if (_string(map, 'version') != version) {
      throw FormatException("delta manifest is for another version, not '$version'");
    }
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
    return DeltaManifest(
      version: version,
      from: from,
      system: manifestSystem,
      archive: archive,
      archiveSha256: archiveSha,
      files: _files(map['files']),
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
