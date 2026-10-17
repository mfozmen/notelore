/// Moving the notes tree to a new home (#207): the visible `~/Notelore` of
/// earlier versions goes into the app's own data folder, so there is one copy
/// and the user never has to see a path.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Moves one file.
typedef MoveFile = void Function(String source, String target);

void _rename(String source, String target) => File(source).renameSync(target);

/// Renames [source] to [target]; across disks, where a rename cannot go,
/// copies it and then deletes the original.
void moveFile(String source, String target, {MoveFile rename = _rename}) {
  try {
    rename(source, target);
  } on FileSystemException {
    File(source).copySync(target); // another disk: rename cannot cross it
    File(source).deleteSync();
  }
}

/// Moves every file under [from] to the same place under [to], then removes
/// [from]'s folders once empty. Never overwrites: a file already there with
/// the same content drops the old copy; a different one keeps the old copy
/// under `.notelore/history/<stamp>/moved/`. A file that cannot move stays
/// where it is and is tried again next time; nothing is lost.
void moveNotes(Directory from, Directory to, {required String stamp, MoveFile move = moveFile}) {
  if (!from.existsSync()) return;
  for (final file in from.listSync(recursive: true).whereType<File>()) {
    final rel = p.relative(file.path, from: from.path);
    var target = p.join(to.path, rel);
    final there = File(target);
    if (there.existsSync()) {
      if (sha256.convert(there.readAsBytesSync()) == sha256.convert(file.readAsBytesSync())) {
        file.deleteSync(); // already in place
        continue;
      }
      target = p.join(to.path, '.notelore', 'history', stamp, 'moved', rel);
    }
    try {
      Directory(p.dirname(target)).createSync(recursive: true);
      move(file.path, target);
    } on FileSystemException {
      // held by another program: it stays, and moves on a later start
    }
  }
  _removeEmpty(from);
}

/// Deletes [dir] and its subfolders that hold no files, deepest first.
void _removeEmpty(Directory dir) {
  for (final sub in dir.listSync().whereType<Directory>()) {
    _removeEmpty(sub);
  }
  if (dir.listSync().isEmpty) dir.deleteSync();
}
