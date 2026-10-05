/// Per-device record of the last synced state, in the state dir.
///
/// For every synced file (keyed by its path relative to the notes root, with `/`):
/// the local content hash, the Drive file id, Drive's `md5Checksum` and
/// `modifiedTime` at that moment, and a copy of the content itself: the base for
/// the next three-way merge. All of it is derived state; losing it only means the
/// next sync compares everything again. The JSON is the Python reference's.
///
/// Keys are case-sensitive while the Windows and macOS file systems are not; the
/// note slugs are lowercase, so two keys differing only in case do not occur.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../store/notes.dart';

/// SHA-256 of the NFC text as UTF-8; macOS may hand back NFD for the same note.
String contentHash(String text) => sha256.convert(utf8.encode(unorm.nfc(text))).toString();

final class ManifestEntry {
  const ManifestEntry({
    required this.localHash,
    required this.driveId,
    required this.md5,
    required this.modified,
  });

  final String localHash;
  final String driveId;

  /// Drive's md5Checksum of the uploaded bytes.
  final String md5;

  /// Drive's modifiedTime, RFC 3339 UTC.
  final String modified;

  Map<String, String> toJson() => {
    'local_hash': localHash,
    'drive_id': driveId,
    'md5': md5,
    'modified': modified,
  };

  @override
  bool operator ==(Object other) =>
      other is ManifestEntry &&
      other.localHash == localHash &&
      other.driveId == driveId &&
      other.md5 == md5 &&
      other.modified == modified;

  @override
  int get hashCode => Object.hash(localHash, driveId, md5, modified);

  @override
  String toString() => 'ManifestEntry(${toJson()})';
}

/// The segments of [rel] as a safe relative path: it can come from Drive, so it
/// is untrusted. Empty, `.` and `..` segments are refused, not normalized.
List<String> checkedRel(String rel) {
  final parts = rel.split('/');
  if (rel.isEmpty ||
      rel.contains(r'\') ||
      rel.contains(':') ||
      parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw ArgumentError.value(rel, 'rel', 'not a safe relative path inside the notes folder');
  }
  return parts;
}

/// A loaded entry, or null when its path is unsafe or its fields are not all strings.
ManifestEntry? _entry(String rel, Object? fields) {
  try {
    checkedRel(rel);
  } on ArgumentError {
    return null;
  }
  if (fields is! Map || fields.length != 4) return null;
  return switch (fields) {
    {
      'local_hash': final String localHash,
      'drive_id': final String driveId,
      'md5': final String md5,
      'modified': final String modified,
    } =>
      ManifestEntry(localHash: localHash, driveId: driveId, md5: md5, modified: modified),
    _ => null,
  };
}

class Manifest {
  Manifest(String stateDir) : _dir = p.join(stateDir, 'sync') {
    _entries.addAll(_load());
  }

  final String _dir;
  final _entries = <String, ManifestEntry>{};

  String get _file => p.join(_dir, 'manifest.json');

  Map<String, ManifestEntry> _load() {
    final Object? raw;
    try {
      raw = jsonDecode(File(_file).readAsStringSync());
    } on FileSystemException {
      return {}; // missing or not UTF-8: derived state, start over
    } on FormatException {
      return {}; // damaged
    }
    if (raw is! Map<String, Object?>) return {};
    return {for (final MapEntry(key: rel, value: fields) in raw.entries) rel: ?_entry(rel, fields)};
  }

  void _save() {
    final data = {for (final rel in paths()) rel: _entries[rel]!.toJson()};
    atomicWrite(_file, '${const JsonEncoder.withIndent(' ').convert(data)}\n');
  }

  String _baseFile(String rel) => p.joinAll([_dir, 'base', ...checkedRel(rel)]);

  List<String> paths() => _entries.keys.toList()..sort();

  ManifestEntry? get(String rel) => _entries[rel];

  String? base(String rel) {
    final path = _baseFile(rel);
    try {
      return File(path).readAsStringSync();
    } on FileSystemException {
      return null; // missing or damaged: no base, the next sync compares all
    }
  }

  /// Remembers [content] as synced: base copy first, so the manifest never points at none.
  void record(String rel, ManifestEntry entry, String content) {
    atomicWrite(_baseFile(rel), content);
    _entries[rel] = entry;
    _save();
  }

  void forget(String rel) {
    final baseFile = File(_baseFile(rel)); // validates rel before anything is written
    _entries.remove(rel);
    _save();
    if (baseFile.existsSync()) baseFile.deleteSync();
  }
}
