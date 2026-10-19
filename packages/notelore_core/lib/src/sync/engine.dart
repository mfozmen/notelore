/// One sync pass over the notes folder against a remote store.
///
/// For every Markdown file under the notes root (`_archive/` and
/// `.notelore/history/` included, so nothing is lost if a device dies), the
/// engine compares the local copy, the remote copy and the manifest's last synced
/// state, lets [decide] pick the action and carries it out. Nothing is hard
/// deleted: a file removed on the other device moves to `.notelore/history/`,
/// and when the model had to settle a real conflict both original sides go there
/// too. Many notes gone from the remote at once (a wiped Drive folder) are held,
/// not removed here, until the person decides (#454). The manifest is updated
/// file by file, so an interrupted sync keeps its progress and simply continues
/// next time.
///
/// The remote is a small interface so the Drive client (and a fake in the tests)
/// plug in the same way. Ported from the Python reference.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../store/notes.dart';
import '../text.dart';
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

  /// Whether the last [list] moved the notes from an older place on the
  /// remote (#454), for the app to say once.
  bool get moved;
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

  /// Gone from the remote, with too many others at once to follow here
  /// unasked: kept, and still in the manifest, so every pass holds them again.
  final held = <String>[];

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
  Set<String> remove = const {},
  Set<String> restore = const {},
}) async {
  final t = (now ?? DateTime.now()).toUtc();
  final stamp =
      '${t.year}-${_two(t.month)}-${_two(t.day)}T${_two(t.hour)}${_two(t.minute)}${_two(t.second)}Z';
  _pruneKept(root, t);
  final local = _localFiles(root);
  // Only notes: anything else in the remote folder (the shared app settings) is
  // not ours to pull, and pulling it would later read as deleted here and trash it.
  final remoteFiles = {
    for (final MapEntry(:key, :value) in (await remote.list()).entries)
      if (_synced(unorm.nfc(key))) unorm.nfc(key): value,
  };
  final report = SyncReport();
  final keys = {...local.keys, ...remoteFiles.keys, ...manifest.paths()}.toList()..sort();
  // Windows and macOS file systems ignore case: two such paths would overwrite each other.
  final folded = <String, int>{};
  for (final key in keys) {
    folded.update(key.toLowerCase(), (n) => n + 1, ifAbsent: () => 1);
  }
  // Only those in [remove], the person's choice, go here too.
  final wiped = _wiped(manifest.paths(), remoteFiles, local);
  bool hold(String rel) => wiped && !remove.contains(rel);
  final run = _Pass(root, manifest, remote, resolve, stamp, report, hold, restore);
  for (final rel in keys) {
    if (!_safe(rel) || folded[rel.toLowerCase()]! > 1) {
      report.ignored.add(rel);
      continue;
    }
    final binary = rel.startsWith('$attachmentsFolder/');
    await (binary ? run.binary : run.file)(rel, remoteFiles[rel], local[rel]);
  }
  return report;
}

/// Whether the notes gone from [remote] look like a wipe, not a tidy-up: all
/// of them, or more than one and more than 3 or a fifth of the notes. Only
/// notes count, with a copy still here: not the archive or history (emptying
/// the archive is a choice made elsewhere), nor a note another device archived
/// (its copy is now under `_archive/`). Moving the notes elsewhere on the
/// remote must list the moved copies from the first pass on, or every one of
/// them reads as gone here and is held.
bool _wiped(List<String> synced, Map<String, RemoteFile> remote, Map<String, File> local) {
  final known = synced.toSet();
  final archived = {
    for (final rel in remote.keys)
      if (rel.startsWith('_archive/') && !known.contains(rel)) rel.split('/').skip(2).join('/'),
  };
  final notes = synced.where(
    (rel) => !rel.startsWith('_archive/') && !rel.startsWith('.notelore/'),
  );
  final gone = notes
      .where((rel) => !remote.containsKey(rel) && local.containsKey(rel) && !archived.contains(rel))
      .length;
  if (gone == 0) return false;
  return !synced.any(remote.containsKey) || (gone > 1 && (gone > 3 || gone * 5 > notes.length));
}

/// The synced files under [root], by their relative path. Keys are NFC: macOS
/// hands back NFD names for the same note Drive stores as NFC.
Map<String, File> _localFiles(String root) => {
  if (Directory(root).existsSync())
    // A link is not followed: nothing outside the notes folder is ever uploaded.
    for (final file in Directory(
      root,
    ).listSync(recursive: true, followLinks: false).whereType<File>())
      if (_synced(_relOf(root, file.path))) _relOf(root, file.path): file,
};

bool _safe(String rel) {
  try {
    checkedRel(rel);
    return true;
  } on ArgumentError {
    return false;
  }
}

/// [path] relative to [root], with forward slashes and in NFC.
String _relOf(String root, String path) =>
    unorm.nfc(p.split(p.relative(path, from: root)).join('/'));

/// Where a pull keeps the copy it replaced (#456): on this device only.
const keptFolder = '.notelore/kept';

/// A pass's folder under [keptFolder]: its UTC stamp, maybe "-2" after it.
final _keptStamp = RegExp(r'^(\d{4})-(\d\d)-(\d\d)T(\d\d)(\d\d)(\d\d)Z(-\d+)?$');

/// Removes the copies a pull kept more than 30 days before [now], so a phone
/// that syncs often does not fill up; a folder by another name stays.
void _pruneKept(String root, DateTime now) {
  final kept = Directory(p.joinAll([root, ...keptFolder.split('/')]));
  if (!kept.existsSync()) return;
  for (final dir in kept.listSync().whereType<Directory>()) {
    final m = _keptStamp.firstMatch(p.basename(dir.path));
    if (m == null) continue;
    final [y, mo, d, h, mi, s] = [for (var i = 1; i <= 6; i++) int.parse(m[i]!)];
    final made = DateTime.utc(y, mo, d, h, mi, s);
    if (now.difference(made) > const Duration(days: 30)) dir.deleteSync(recursive: true);
  }
}

/// Notes, and the originals kept beside them (#279); nothing else in the folder,
/// nor a write's temp file left by a crash (a dot file), nor what a pull kept.
bool _synced(String rel) =>
    !rel.startsWith('$keptFolder/') &&
    (rel.endsWith('.md') ||
        (rel.startsWith('$attachmentsFolder/') && !rel.split('/').last.startsWith('.')));

class _Pass {
  _Pass(
    this.root,
    this.manifest,
    this.remote,
    this.resolve,
    this.stamp,
    this.report,
    this.hold,
    this.restore,
  );

  final String root;
  final Manifest manifest;
  final Remote remote;
  final Resolver resolve;
  final String stamp;
  final SyncReport report;
  final bool Function(String rel) hold;

  /// Gone from the remote, and to be put back there: pushed, not removed here.
  final Set<String> restore;

  SyncAction _action(String rel, String? base, String? local, String? remote) {
    final action = decide(base, local, remote);
    return action == SyncAction.removeLocal && restore.contains(rel) ? SyncAction.push : action;
  }

  String _path(String rel, [String? base]) => p.joinAll([base ?? root, ...rel.split('/')]);

  String _history(String rel) => _path(rel, p.join(root, '.notelore', 'history', stamp));

  String _rel(String path) => p.split(p.relative(path, from: root)).join('/');

  Future<void> file(String rel, RemoteFile? meta, File? found) async {
    // The name on disk may be NFD; new files are written NFC.
    final path = found?.path ?? _path(rel);
    final entry = manifest.get(rel);
    final trusted = _trusted(entry, meta);
    final baseHash = trusted?.localHash;
    final texts = await _texts(found, meta, trusted);
    // Not UTF-8: one bad file never stops the rest.
    if (texts == null) return report.skipped.add(rel);
    final (localText, remoteText) = texts;
    final remoteHash = _remoteHash(meta, remoteText, baseHash);
    final localHash = localText == null ? null : contentHash(localText);

    switch (_action(rel, baseHash, localHash, remoteHash)) {
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
        if (!_unchanged(path, localText)) return report.skipped.add(rel);
        if (localText != null && _loses(localText, remoteText!)) {
          _keepCopy(rel, utf8.encode(localText));
        }
        atomicWrite(path, remoteText!);
        _record(rel, meta!, remoteText);
        report.pulled.add(rel);
      case SyncAction.merge:
        final base = trusted == null ? null : manifest.base(rel);
        await _merge(rel, path, meta!, localText!, remoteText!, base ?? '');
      case SyncAction.removeLocal:
        _removeLocal(rel, path);
      case SyncAction.removeRemote:
        await remote.trash(meta!.id);
        manifest.forget(rel);
        report.removedRemote.add(rel);
    }
  }

  /// An attachment (#279): its bytes travel as they are, never merged. Changed
  /// on both sides, Drive's copy stays and this one goes to history.
  Future<void> binary(String rel, RemoteFile? meta, File? found) async {
    final path = found?.path ?? _path(rel);
    final entry = _trusted(manifest.get(rel), meta);
    final local = found?.readAsBytesSync();
    final untouched = meta == null || (entry != null && meta.md5 == entry.md5);
    final downloaded = untouched ? null : await remote.download(meta.id);
    final localHash = local == null ? null : bytesHash(local);
    // Unchanged on Drive: its bytes are the ones last synced.
    var remoteHash = meta == null ? null : entry?.localHash;
    if (downloaded != null) remoteHash = bytesHash(downloaded);
    ManifestEntry recorded(RemoteFile at, String hash) =>
        ManifestEntry(localHash: hash, driveId: at.id, md5: at.md5, modified: at.modified);
    switch (_action(rel, entry?.localHash, localHash, remoteHash)) {
      case SyncAction.none:
        if (local != null && meta != null) {
          if (entry != recorded(meta, localHash!)) manifest.record(rel, recorded(meta, localHash));
        } else {
          manifest.forget(rel);
        }
      case SyncAction.push:
        final uploaded = await remote.upload(rel, local!, meta?.id);
        manifest.record(rel, recorded(uploaded, localHash!));
        report.pushed.add(rel);
      case SyncAction.pull:
        if (local != null) _keepCopy(rel, local); // bytes cannot tell a loss: always kept
        _take(rel, path, meta!, downloaded!, recorded(meta, remoteHash!));
      case SyncAction.merge:
        // Changed here too: this copy is kept apart before Drive's replaces it.
        final target = _history(rel);
        Directory(p.dirname(target)).createSync(recursive: true);
        moveWithRetry(path, target);
        report.history.add(_rel(target));
        _take(rel, path, meta!, downloaded!, recorded(meta, remoteHash!));
      case SyncAction.removeLocal:
        _removeLocal(rel, path);
      case SyncAction.removeRemote:
        await remote.trash(meta!.id);
        manifest.forget(rel);
        report.removedRemote.add(rel);
    }
  }

  /// The manifest's [entry], unless the remote file is another one with other
  /// content: the last sync's base then says nothing about it (the notes moved
  /// on the remote while another device still wrote to the old place, #454),
  /// and taking Drive's copy over an edit here would lose the edit. The price:
  /// a note another device changed after the move, and this one did not,
  /// merges against nothing on this device's first sync after it, so it may
  /// come up as one conflict for the model, never as a loss.
  static ManifestEntry? _trusted(ManifestEntry? entry, RemoteFile? meta) =>
      entry != null && meta != null && meta.id != entry.driveId && meta.md5 != entry.md5
      ? null
      : entry;

  /// Gone from the remote: the copy here moves to history, unless held.
  void _removeLocal(String rel, String path) {
    if (hold(rel)) return report.held.add(rel);
    final target = _history(rel);
    Directory(p.dirname(target)).createSync(recursive: true);
    moveWithRetry(path, target);
    manifest.forget(rel);
    report
      ..removedLocal.add(rel)
      ..history.add(_rel(target));
  }

  /// Keeps [bytes], what is here, under `.notelore/kept/` before Drive's copy
  /// replaces it (#456): a damaged remote, or a buggy client, never takes the
  /// last good copy. On this device only (never synced): every device that
  /// had the lines keeps its own, and routine edits do not pile up on Drive.
  void _keepCopy(String rel, List<int> bytes) {
    var target = _path(rel, p.join(root, keptFolder, stamp));
    // Two passes in one second: the first copy stays too.
    for (var n = 2; File(target).existsSync(); n++) {
      target = _path(rel, p.join(root, keptFolder, '$stamp-$n'));
    }
    atomicWriteBytes(target, bytes);
    report.history.add(_rel(target));
  }

  /// Whether [remote] lacks a line of [local] (counting repeats): a pull that
  /// only adds (another device's entry, the usual edit) loses nothing and keeps
  /// no copy. The updated date does not count: it changes every time.
  static bool _loses(String local, String remote) {
    List<String> lines(String text) => splitLines(unorm.nfc(text.replaceAll('\r\n', '\n')));
    final there = <String, int>{};
    for (final line in lines(remote)) {
      there.update(line, (n) => n + 1, ifAbsent: () => 1);
    }
    for (final line in lines(local)) {
      if (line.trim().isEmpty || line.startsWith('updated:')) continue;
      final left = there[line] ?? 0;
      if (left == 0) return true;
      there[line] = left - 1;
    }
    return false;
  }

  /// Drive's copy of an attachment, written here and recorded.
  void _take(String rel, String path, RemoteFile meta, List<int> bytes, ManifestEntry entry) {
    atomicWriteBytes(path, bytes);
    manifest.record(rel, entry);
    report.pulled.add(rel);
  }

  /// The local text and the remote one, downloaded only when Drive changed it
  /// since the last sync; null when either is not UTF-8.
  Future<(String?, String?)?> _texts(File? found, RemoteFile? meta, ManifestEntry? entry) async {
    try {
      final local = found == null ? null : utf8.decode(found.readAsBytesSync());
      final untouched = meta == null || (entry != null && meta.md5 == entry.md5);
      return (local, untouched ? null : utf8.decode(await remote.download(meta.id)));
    } on FormatException {
      return null;
    }
  }

  /// The remote side's hash: none when it is gone, the base's when untouched
  /// since the last sync (not downloaded), else that of what was downloaded.
  static String? _remoteHash(RemoteFile? meta, String? downloaded, String? baseHash) {
    if (meta == null) return null;
    return downloaded == null ? baseHash : contentHash(downloaded);
  }

  /// The file still holds what this pass read before downloading (seconds
  /// earlier): a note saved meanwhile in another editor is never written over.
  bool _unchanged(String path, String? read) {
    final now = File(path);
    return (now.existsSync() ? utf8.decode(now.readAsBytesSync(), allowMalformed: true) : null) ==
        read;
  }

  ManifestEntry _entry(RemoteFile meta, String text) => ManifestEntry(
    localHash: contentHash(text),
    driveId: meta.id,
    md5: meta.md5,
    modified: meta.modified,
  );

  void _record(String rel, RemoteFile meta, String text) =>
      manifest.record(rel, _entry(meta, text), text);

  /// [base] is empty with none (first sync, a damaged copy, or one not trusted):
  /// the whole file is then one conflict, which goes to the model or is
  /// skipped, never guessed.
  Future<void> _merge(
    String rel,
    String path,
    RemoteFile meta,
    String localText,
    String remoteText,
    String base,
  ) async {
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
    // Drive has the merge; the next sync merges it with what was saved here meanwhile.
    if (!_unchanged(path, localText)) return report.skipped.add(rel);
    atomicWrite(path, text);
    _record(rel, uploaded, text);
    report.merged.add(rel);
  }
}
