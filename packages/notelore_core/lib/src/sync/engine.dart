/// One sync pass over the notes folder against a remote store.
///
/// For every Markdown file under the notes root (`_archive/` and
/// `.notelore/history/` included, so nothing is lost if a device dies), the
/// engine compares the local copy, the remote copy and the manifest's last synced
/// state, lets [decide] pick the action and carries it out. Nothing is hard
/// deleted: a file removed on the other device moves to `.notelore/history/`,
/// and when the model had to settle a real conflict both original sides go there
/// too. The manifest is updated file by file, so an interrupted sync keeps its
/// progress and simply continues next time.
///
/// The remote is a small interface so the Drive client (and a fake in the tests)
/// plug in the same way. Ported from the Python reference.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../store/notes.dart';
import 'manifest.dart';
import 'merge.dart';

final class RemoteFile {
  const RemoteFile({required this.id, required this.md5, required this.modified});

  final String id;
  final String md5;
  final String modified;
}

abstract interface class Remote {
  /// Every remote file by path relative to the notes root.
  Future<Map<String, RemoteFile>> list();

  Future<List<int>> download(String fileId);

  /// Creates the file ([fileId] null) or replaces its content.
  Future<RemoteFile> upload(String rel, List<int> data, String? fileId);

  /// Moves to the remote trash: reversible, never a hard delete.
  Future<void> trash(String fileId);
}

class SyncReport {
  final pushed = <String>[];
  final pulled = <String>[];
  final merged = <String>[];
  final removedLocal = <String>[];
  final removedRemote = <String>[];

  /// Unresolved conflict or not UTF-8: retried next time.
  final skipped = <String>[];

  /// Unsafe remote paths, or paths that differ only in case.
  final ignored = <String>[];

  /// Copies kept under `.notelore/history/`.
  final history = <String>[];

  int get changed =>
      pushed.length + pulled.length + merged.length + removedLocal.length + removedRemote.length;
}

String _two(int n) => n.toString().padLeft(2, '0');

Future<SyncReport> sync(
  String root,
  Manifest manifest,
  Remote remote,
  Resolver resolve, {
  DateTime? now,
}) async {
  final t = (now ?? DateTime.now()).toUtc();
  final stamp =
      '${t.year}-${_two(t.month)}-${_two(t.day)}T${_two(t.hour)}${_two(t.minute)}${_two(t.second)}Z';
  // Keys are NFC: macOS hands back NFD names for the same note Drive stores as NFC.
  final local = <String, File>{
    if (Directory(root).existsSync())
      for (final file in Directory(root).listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.md'))
          unorm.nfc(p.split(p.relative(file.path, from: root)).join('/')): file,
  };
  final remoteFiles = {
    for (final MapEntry(:key, :value) in (await remote.list()).entries) unorm.nfc(key): value,
  };
  final report = SyncReport();
  final keys = {...local.keys, ...remoteFiles.keys, ...manifest.paths()}.toList()..sort();
  // Windows and macOS file systems ignore case: two such paths would overwrite each other.
  final folded = <String, int>{};
  for (final key in keys) {
    folded.update(key.toLowerCase(), (n) => n + 1, ifAbsent: () => 1);
  }
  final run = _Pass(root, manifest, remote, resolve, stamp, report);
  for (final rel in keys) {
    try {
      checkedRel(rel);
    } on ArgumentError {
      report.ignored.add(rel);
      continue;
    }
    if (folded[rel.toLowerCase()]! > 1) {
      report.ignored.add(rel);
      continue;
    }
    await run.file(rel, remoteFiles[rel], local[rel]);
  }
  return report;
}

class _Pass {
  _Pass(this.root, this.manifest, this.remote, this.resolve, this.stamp, this.report);

  final String root;
  final Manifest manifest;
  final Remote remote;
  final Resolver resolve;
  final String stamp;
  final SyncReport report;

  String _path(String rel, [String? base]) => p.joinAll([base ?? root, ...rel.split('/')]);

  String _history(String rel) => _path(rel, p.join(root, '.notelore', 'history', stamp));

  String _rel(String path) => p.split(p.relative(path, from: root)).join('/');

  Future<void> file(String rel, RemoteFile? meta, File? found) async {
    // The name on disk may be NFD; new files are written NFC.
    final path = found?.path ?? _path(rel);
    final entry = manifest.get(rel);
    final baseHash = entry?.localHash;
    final String? localText;
    String? remoteText;
    final String? remoteHash;
    try {
      localText = found == null ? null : utf8.decode(found.readAsBytesSync());
      if (meta == null) {
        remoteHash = null;
      } else if (entry != null && meta.md5 == entry.md5) {
        remoteHash = baseHash; // untouched since the last sync: no download needed
      } else {
        remoteText = utf8.decode(await remote.download(meta.id));
        remoteHash = contentHash(remoteText);
      }
    } on FormatException {
      report.skipped.add(rel); // not a UTF-8 note; one bad file never stops the rest
      return;
    }
    final localHash = localText == null ? null : contentHash(localText);

    switch (decide(baseHash, localHash, remoteHash)) {
      case SyncAction.none:
        if (localText != null && meta != null) {
          if (entry != _entry(meta, localText)) _record(rel, meta, localText);
        } else {
          manifest.forget(rel); // gone on both sides; listed only because the manifest knew it
        }
      case SyncAction.push:
        final uploaded = await remote.upload(rel, utf8.encode(localText!), meta?.id);
        _record(rel, uploaded, localText);
        report.pushed.add(rel);
      case SyncAction.pull:
        atomicWrite(path, remoteText!);
        _record(rel, meta!, remoteText);
        report.pulled.add(rel);
      case SyncAction.merge:
        await _merge(rel, path, meta!, localText!, remoteText!);
      case SyncAction.removeLocal:
        final target = _history(rel);
        Directory(p.dirname(target)).createSync(recursive: true);
        moveWithRetry(path, target);
        manifest.forget(rel);
        report
          ..removedLocal.add(rel)
          ..history.add(_rel(target));
      case SyncAction.removeRemote:
        await remote.trash(meta!.id);
        manifest.forget(rel);
        report.removedRemote.add(rel);
    }
  }

  ManifestEntry _entry(RemoteFile meta, String text) => ManifestEntry(
    localHash: contentHash(text),
    driveId: meta.id,
    md5: meta.md5,
    modified: meta.modified,
  );

  void _record(String rel, RemoteFile meta, String text) =>
      manifest.record(rel, _entry(meta, text), text);

  Future<void> _merge(
    String rel,
    String path,
    RemoteFile meta,
    String localText,
    String remoteText,
  ) async {
    // No base (first sync, or a damaged copy) merges against empty: the whole file is
    // then one conflict, which goes to the model or is skipped, never guessed.
    final base = manifest.base(rel) ?? '';
    var askedModel = false;
    final String text;
    try {
      text = await threeWay(base, localText, remoteText).text((conflict) {
        final lines = autoResolve(conflict);
        if (lines != null) return lines;
        askedModel = true;
        return resolve(conflict);
      });
    } on UnresolvedConflicts {
      report.skipped.add(rel); // nothing written or recorded: retried next time
      return;
    }
    // Upload first: if it fails, neither side has changed and the next sync starts over.
    final uploaded = await remote.upload(rel, utf8.encode(text), meta.id);
    if (askedModel) {
      // the losing sides stay available, never silently dropped
      for (final (side, content) in [('local', localText), ('remote', remoteText)]) {
        final history = _history(rel);
        final kept = p.join(
          p.dirname(history),
          '${p.basenameWithoutExtension(history)}.$side${p.extension(history)}',
        );
        atomicWrite(kept, content);
        report.history.add(_rel(kept));
      }
    }
    atomicWrite(path, text);
    _record(rel, uploaded, text);
    report.merged.add(rel);
  }
}
