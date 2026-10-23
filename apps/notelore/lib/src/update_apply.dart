/// Applies a staged changed-files Windows update after the app has exited
/// (#584). The small helper (`tool/update_helper.dart`) uses this; tests cover
/// it with temp folders.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'update_delta.dart'
    show isSafeUpdatePath, updateJsonFiles, updateJsonObject, updateJsonString;

const _what = 'update job';

class UpdateApplyFailed implements Exception {
  const UpdateApplyFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

int _parentPid(Object? value) {
  if (value is! int || value <= 0) {
    throw const FormatException('update job has no parent pid');
  }
  return value;
}

String _executable(Map<String, Object?> map) {
  final value = updateJsonString(map, 'executable', _what);
  if (!isSafeUpdatePath(value) || value.contains('/')) {
    throw FormatException("update job executable '$value' is not a plain name");
  }
  return value;
}

/// The job the app leaves for the helper: [install] is the app folder,
/// [staging] the verified files, and [files] their relative paths and hashes.
final class UpdateJob {
  const UpdateJob({
    required this.install,
    required this.staging,
    required this.files,
    required this.executable,
    required this.parentPid,
  });

  final String install;
  final String staging;
  final Map<String, String> files;
  final String executable;
  final int parentPid;

  factory UpdateJob.fromJson(String text) {
    final map = updateJsonObject(text, _what);
    final install = updateJsonString(map, 'install', _what);
    final staging = updateJsonString(map, 'staging', _what);
    if (!p.isAbsolute(install) || !p.isAbsolute(staging)) {
      throw const FormatException('update job paths must be absolute');
    }
    return UpdateJob(
      install: install,
      staging: staging,
      files: updateJsonFiles(map['files'], _what),
      executable: _executable(map),
      parentPid: _parentPid(map['parent_pid']),
    );
  }

  Map<String, Object?> toJson() => {
    'install': install,
    'staging': staging,
    'files': files,
    'executable': executable,
    'parent_pid': parentPid,
  };
}

/// Copies every staged file into place, verifying its hash before and after.
/// On any failure every touched file is put back from the backup; throws
/// [UpdateApplyFailed].
Future<void> applyUpdate(UpdateJob job, {void Function(String message)? log}) async {
  final install = Directory(job.install);
  final staging = Directory(job.staging);
  if (!install.existsSync()) throw UpdateApplyFailed('no app folder at ${job.install}');
  if (!staging.existsSync()) throw UpdateApplyFailed('no staging folder at ${job.staging}');
  final backup = Directory(p.join(install.path, '.notelore-backup'));
  if (backup.existsSync()) backup.deleteSync(recursive: true);
  backup.createSync(recursive: true);
  final touched = <String>[];
  try {
    for (final MapEntry(key: path, value: hash) in job.files.entries) {
      _copyOne(install.path, staging.path, backup.path, path, hash, touched);
    }
    backup.deleteSync(recursive: true);
    log?.call('updated ${job.files.length} files');
  } on Object {
    _restore(install.path, backup.path, touched);
    backup.deleteSync(recursive: true);
    rethrow;
  }
}

void _copyOne(
  String install,
  String staging,
  String backup,
  String path,
  String hash,
  List<String> touched,
) {
  final staged = File(_under(staging, path));
  if (!staged.existsSync()) throw UpdateApplyFailed('staged file $path is missing');
  if (_hash(staged) != hash) throw UpdateApplyFailed('staged file $path has the wrong hash');
  final target = File(_under(install, path));
  final saved = File(_under(backup, path));
  saved.parent.createSync(recursive: true);
  if (target.existsSync()) target.copySync(saved.path);
  final temp = File('${target.path}.notelore-tmp');
  staged.copySync(temp.path);
  if (_hash(temp) != hash) throw UpdateApplyFailed('copied file $path has the wrong hash');
  touched.add(path);
  if (target.existsSync()) target.deleteSync();
  temp.renameSync(target.path);
  if (_hash(target) != hash) throw UpdateApplyFailed('installed file $path has the wrong hash');
}

String _under(String root, String relative) => p.joinAll([root, ...relative.split('/')]);

String _hash(File file) => sha256.convert(file.readAsBytesSync()).toString();

void _restore(String install, String backup, Iterable<String> paths) {
  for (final path in paths) {
    final target = File(_under(install, path));
    final saved = File(_under(backup, path));
    final temp = File('${target.path}.notelore-tmp');
    if (temp.existsSync()) temp.deleteSync();
    if (saved.existsSync()) {
      target.parent.createSync(recursive: true);
      if (target.existsSync()) target.deleteSync();
      saved.copySync(target.path);
    } else if (target.existsSync()) {
      target.deleteSync();
    }
  }
}
