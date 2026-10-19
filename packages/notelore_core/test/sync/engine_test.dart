import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:notelore_core/src/sync/engine.dart';
import 'package:notelore_core/src/sync/manifest.dart';
import 'package:notelore_core/src/sync/merge.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../support/files.dart';

final now = DateTime.utc(2026, 10, 1, 9, 30, 5);
const stamp = '2026-10-01T093005Z';
const note =
    '---\ntitle: T\nupdated: 2026-09-01\n---\n# T\n\n## Notes\n- 2026-09-01: one\n\n## Todo\n';

/// In-memory Drive: files by relative path, md5 like Drive's md5Checksum.
class FakeDrive implements Remote {
  final files = <String, (String, List<int>)>{}; // rel -> (id, data)
  final trashed = <String>[];
  var uploads = 0;
  var offline = false;
  @override
  var moved = false;
  var _next = 0;

  /// Runs during a download: the user saving the note in another editor meanwhile.
  void Function()? whileDownloading;

  void put(String rel, String text) => files[rel] = (files[rel]?.$1 ?? _newId(), utf8.encode(text));

  String _newId() => 'id${++_next}';

  String text(String rel) => utf8.decode(files[rel]!.$2);

  void putBytes(String rel, List<int> data) => files[rel] = (files[rel]?.$1 ?? _newId(), data);

  List<int> bytes(String rel) => files[rel]!.$2;

  RemoteFile _meta(String rel) {
    final (id, data) = files[rel]!;
    return RemoteFile(id: id, md5: md5.convert(data).toString(), modified: 't${data.length}');
  }

  @override
  Future<Map<String, RemoteFile>> list() async => {for (final rel in files.keys) rel: _meta(rel)};

  @override
  Future<List<int>> download(String fileId) async {
    whileDownloading?.call();
    return files.values.firstWhere((file) => file.$1 == fileId).$2;
  }

  @override
  Future<RemoteFile> upload(String rel, List<int> data, String? fileId) async {
    if (offline) throw const SocketException('offline');
    uploads++;
    expect(fileId, anyOf(isNull, files[rel]?.$1));
    files[rel] = (fileId ?? _newId(), data);
    return _meta(rel);
  }

  @override
  Future<void> trash(String fileId) async {
    final rel = files.keys.firstWhere((rel) => files[rel]!.$1 == fileId);
    files.remove(rel);
    trashed.add(rel);
  }
}

List<String>? never(Conflict conflict) => fail('the model must not be asked');

void main() {
  late String root;
  late Manifest manifest;
  late FakeDrive drive;
  setUp(() {
    final dir = tempDir();
    root = p.join(dir, 'notes');
    manifest = Manifest(p.join(dir, 'state'));
    drive = FakeDrive();
  });

  String at(String rel) => p.joinAll([root, ...rel.split('/')]);
  void write(String rel, String text) => File(at(rel))
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(utf8.encode(text));
  String readRel(String rel) => read(at(rel));
  Future<SyncReport> run({
    Resolver resolve = never,
    Set<String> remove = const {},
    Set<String> restore = const {},
  }) => sync(root, manifest, drive, resolve, now: now, remove: remove, restore: restore);

  test('the first sync pushes everything and the second does nothing', () async {
    write('projects/a.md', note);
    write('_archive/2026-01-01/topics/old.md', note);
    write('notes-outside-kinds.txt', 'ignored, not markdown');
    final report = await run();
    expect(report.pushed, ['_archive/2026-01-01/topics/old.md', 'projects/a.md']);
    expect(drive.text('projects/a.md'), note);
    expect(manifest.base('projects/a.md'), note);
    expect((await run()).changed, 0);
    expect(drive.uploads, 2);
  });

  test('a link in the notes folder is not followed: nothing outside is uploaded (#315)', () async {
    final outside = Directory(p.join(p.dirname(root), 'private'))..createSync(recursive: true);
    File(p.join(outside.path, 'secret.md')).writeAsStringSync(note);
    write('projects/a.md', note);
    Link(at('projects/elsewhere')).createSync(outside.path);
    final report = await run();
    expect(report.pushed, ['projects/a.md']);
  });

  test('an attachment travels as it is: pushed, pulled, never merged (#279)', () async {
    final bytes = [0, 255, 1, 254]; // not text
    File(at('attachments/2026-10-18/memo.m4a'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    // A write cut off by a crash leaves its temp file: never uploaded.
    File(at('attachments/2026-10-18/.memo.m4a.0a1b.tmp')).writeAsBytesSync([5]);
    var report = await run();
    expect(report.pushed, ['attachments/2026-10-18/memo.m4a']);
    expect(drive.bytes('attachments/2026-10-18/memo.m4a'), bytes);
    expect((await run()).changed, 0);
    // One made on another device comes down.
    drive.putBytes('attachments/2026-10-19/call.ogg', [7, 7, 7]);
    report = await run();
    expect(report.pulled, ['attachments/2026-10-19/call.ogg']);
    expect(File(at('attachments/2026-10-19/call.ogg')).readAsBytesSync(), [7, 7, 7]);
    // Changed on both sides: Drive's copy stays, this one goes to history, nothing lost.
    File(at('attachments/2026-10-19/call.ogg')).writeAsBytesSync([1]);
    drive.putBytes('attachments/2026-10-19/call.ogg', [2]);
    report = await run();
    expect(File(at('attachments/2026-10-19/call.ogg')).readAsBytesSync(), [2]);
    expect(report.history.single, endsWith('attachments/2026-10-19/call.ogg'));
    expect(File(p.join(root, report.history.single)).readAsBytesSync(), [1]);
    // Deleted here: trashed on Drive, never hard deleted.
    File(at('attachments/2026-10-18/memo.m4a')).deleteSync();
    report = await run();
    expect(report.removedRemote, ['attachments/2026-10-18/memo.m4a']);
    // Trashed on Drive (with a note still there, so not a wipe, #454): here it
    // goes to history, never deleted.
    write('topics/stays.md', note);
    await run();
    drive.files.remove('attachments/2026-10-19/call.ogg');
    report = await run();
    expect(report.removedLocal, ['attachments/2026-10-19/call.ogg']);
    expect(File(at('attachments/2026-10-19/call.ogg')).existsSync(), isFalse);
    // Gone on both sides with the manifest still knowing it: forgotten quietly.
    File(at('attachments/2026-10-20/x.wav'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([3]);
    await run();
    File(at('attachments/2026-10-20/x.wav')).deleteSync();
    drive.files.remove('attachments/2026-10-20/x.wav');
    expect((await run()).changed, 0);
    expect(manifest.get('attachments/2026-10-20/x.wav'), isNull);
  });

  test('a new remote file is pulled', () async {
    drive.put('topics/from-mac.md', note);
    expect((await run()).pulled, ['topics/from-mac.md']);
    expect(readRel('topics/from-mac.md'), note);
    expect(manifest.get('topics/from-mac.md'), isNotNull);
  });

  test('one-sided edits push or pull', () async {
    write('projects/a.md', note);
    await run();
    write('projects/a.md', '$note- [ ] 2026-10-01: local\n');
    expect((await run()).pushed, ['projects/a.md']);
    drive.put('projects/a.md', '$note- [ ] 2026-10-01: local\n- [ ] 2026-10-02: remote\n');
    expect((await run()).pulled, ['projects/a.md']);
    expect(readRel('projects/a.md'), endsWith('- [ ] 2026-10-02: remote\n'));
    expect(Directory(p.join(root, '.notelore', 'kept')).existsSync(), isFalse); // nothing lost
  });

  group('a pull that would lose lines keeps this copy on the device (#456)', () {
    const kept = '.notelore/kept/$stamp/projects/a.md';

    test("Drive's copy without lines this one has", () async {
      write('projects/a.md', '$note- 2026-09-02: two\n');
      await run();
      // A damaged copy, or a buggy client: the entries are gone on Drive.
      drive.put('projects/a.md', '---\ntitle: T\nupdated: 2026-09-01\n---\n# T\n');
      final report = await run();
      expect(report.pulled, ['projects/a.md']);
      expect(report.history, [kept]);
      expect(readRel(kept), '$note- 2026-09-02: two\n');
      expect(readRel('projects/a.md'), isNot(contains('two')));
      // On this device only: never sent to Drive, so routine edits do not pile up there.
      expect((await run()).changed, 0);
      expect(drive.files.keys.where((rel) => rel.contains('kept')), isEmpty);
    });

    test('one of two equal lines gone, or a front matter key, is a loss', () async {
      write(
        'projects/a.md',
        '$note- [ ] 2026-09-02: call the bank\n- [ ] 2026-09-02: call the bank\n',
      );
      await run();
      drive.put('projects/a.md', '$note- [ ] 2026-09-02: call the bank\n');
      expect((await run()).history, [kept]);
      write('topics/t.md', note);
      await run();
      drive.put('topics/t.md', note.replaceFirst('title: T', 'title: Other'));
      expect((await run()).history.single, endsWith('topics/t.md'));
    });

    test('a changed updated date, line endings or Unicode form lose nothing', () async {
      write('projects/a.md', note.replaceAll('\n', '\r\n'));
      await run();
      drive.put('projects/a.md', note.replaceFirst('updated: 2026-09-01', 'updated: 2026-10-01'));
      expect((await run()).history, isEmpty);
      write('topics/cafe.md', '${unorm.nfd(note.replaceFirst('# T', '# Café'))}- 2026-09-02: x\n');
      await run();
      drive.put('topics/cafe.md', '${note.replaceFirst('# T', '# Café')}- 2026-09-02: x\n- y\n');
      expect((await run()).history, isEmpty);
    });

    test('a second copy in the same second keeps the first', () async {
      write('projects/a.md', '$note- 2026-09-02: one\n');
      await run();
      drive.put('projects/a.md', note);
      await run();
      write('projects/a.md', '$note- 2026-09-02: two\n');
      await run();
      drive.put('projects/a.md', note);
      expect((await run()).history, ['.notelore/kept/$stamp-2/projects/a.md']);
      expect(readRel(kept), contains('one'));
    });

    test('an attachment Drive changed keeps the bytes it replaces', () async {
      File(at('attachments/2026-10-18/memo.m4a'))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync([1, 2]);
      await run();
      drive.putBytes('attachments/2026-10-18/memo.m4a', [3]);
      final report = await run();
      expect(report.history, ['.notelore/kept/$stamp/attachments/2026-10-18/memo.m4a']);
      expect(File(at('.notelore/kept/$stamp/attachments/2026-10-18/memo.m4a')).readAsBytesSync(), [
        1,
        2,
      ]);
      expect(File(at('attachments/2026-10-18/memo.m4a')).readAsBytesSync(), [3]);
    });
  });

  test('edits on both sides in different places merge', () async {
    write('projects/a.md', note);
    await run();
    write(
      'projects/a.md',
      note
          .replaceAll('updated: 2026-09-01', 'updated: 2026-09-05')
          .replaceFirst('- 2026-09-01: one\n', '- 2026-09-01: one\n- 2026-09-05: laptop\n'),
    );
    drive.put(
      'projects/a.md',
      '${note.replaceAll('updated: 2026-09-01', 'updated: 2026-09-07')}- [ ] 2026-09-07: mac\n',
    );
    final report = await run(); // the updated: clash never reaches the model
    expect(report.merged, ['projects/a.md']);
    final merged = readRel('projects/a.md');
    expect(merged, contains('updated: 2026-09-07\n'));
    expect(merged, allOf(contains('- 2026-09-05: laptop\n'), contains('- [ ] 2026-09-07: mac\n')));
    expect(drive.text('projects/a.md'), merged);
    expect(manifest.base('projects/a.md'), merged);
    expect(report.history, isEmpty);
  });

  test('an edit saved while the sync downloads is never written over (#249)', () async {
    write('projects/a.md', note);
    await run();
    // Pull: only the remote changed, but the user saves here during the download.
    const remote = '- [ ] 2026-10-02: remote\n';
    const saved = '- [ ] 2026-10-03: saved here\n';
    const again = '- [ ] 2026-10-04: again\n';
    drive.put('projects/a.md', '$note$remote');
    drive.whileDownloading = () => write('projects/a.md', '$note$saved');
    final pulled = await run();
    expect(pulled.skipped, ['projects/a.md']);
    expect(readRel('projects/a.md'), endsWith(saved));
    // Merge: both changed, and the user saves again during the download.
    drive.whileDownloading = () => write('projects/a.md', '$note$saved$again');
    final merged = await run();
    expect(merged.skipped, ['projects/a.md']);
    expect(readRel('projects/a.md'), endsWith(again));
    // Nothing more saved meanwhile: the next sync keeps every edit.
    drive.whileDownloading = null;
    expect((await run()).merged, ['projects/a.md']);
    expect(
      readRel('projects/a.md'),
      allOf(contains('remote'), contains('saved here'), contains('again')),
    );
  });

  test('a real conflict asks the resolver and keeps both sides', () async {
    write('projects/a.md', note);
    await run();
    write('projects/a.md', note.replaceAll('one', 'laptop wording'));
    drive.put('projects/a.md', note.replaceAll('one', 'mac wording'));
    final asked = <Conflict>[];
    final report = await run(
      resolve: (conflict) async {
        asked.add(conflict);
        return conflict.remote;
      },
    );
    expect(asked, hasLength(1));
    expect(readRel('projects/a.md'), contains('mac wording'));
    expect(readRel('.notelore/history/$stamp/projects/a.local.md'), contains('laptop wording'));
    expect(readRel('.notelore/history/$stamp/projects/a.remote.md'), contains('mac wording'));
    expect(report.history, [
      '.notelore/history/$stamp/projects/a.local.md',
      '.notelore/history/$stamp/projects/a.remote.md',
    ]);
  });

  test('an unresolved conflict is skipped and retried later', () async {
    write('projects/a.md', note);
    await run();
    final local = note.replaceAll('one', 'laptop');
    write('projects/a.md', local);
    drive.put('projects/a.md', note.replaceAll('one', 'mac'));
    final report = await run(resolve: (conflict) => null);
    expect(report.skipped, ['projects/a.md']);
    expect(readRel('projects/a.md'), local);
    expect(drive.text('projects/a.md'), contains('mac'));
    expect(manifest.base('projects/a.md'), note); // nothing recorded: the next sync tries again
  });

  test('archiving locally trashes the remote copy', () async {
    write('projects/a.md', note);
    await run();
    File(at('projects/a.md')).deleteSync(); // what archiveNote does, as the sync sees it
    write('_archive/2026-10-01/projects/a.md', note);
    final report = await run();
    expect(report.removedRemote, ['projects/a.md']);
    expect(drive.trashed, ['projects/a.md']);
    expect(manifest.get('projects/a.md'), isNull);
    expect(drive.files, contains('_archive/2026-10-01/projects/a.md'));
  });

  test('a remote removal moves the local copy to history', () async {
    write('topics/t.md', note);
    write('topics/stays.md', note);
    await run();
    drive.files.remove('topics/t.md');
    final report = await run();
    expect(report.removedLocal, ['topics/t.md']);
    expect(File(at('topics/t.md')).existsSync(), isFalse);
    expect(readRel('.notelore/history/$stamp/topics/t.md'), note);
    expect(report.history, ['.notelore/history/$stamp/topics/t.md']);
    expect(manifest.get('topics/t.md'), isNull);
  });

  test('many notes gone from Drive at once are held, never removed here (#454)', () async {
    for (final name in ['a', 'b', 'c', 'd', 'e']) {
      write('topics/$name.md', note);
    }
    write('attachments/x.png', 'png');
    await run();
    // "Delete hidden app data" in Drive's settings, or a wiped folder.
    drive.files.clear();
    final report = await run();
    expect(report.held, [
      'attachments/x.png',
      'topics/a.md',
      'topics/b.md',
      'topics/c.md',
      'topics/d.md',
      'topics/e.md',
    ]);
    expect(report.removedLocal, isEmpty);
    expect(report.changed, 0);
    expect(File(at('topics/a.md')).existsSync(), isTrue);
    expect(manifest.get('topics/a.md'), isNotNull); // still held on the next pass
    expect((await run()).held, hasLength(6));
    // The person chose "Delete them here too" for these two only.
    final removed = await run(remove: {'topics/a.md', 'attachments/x.png'});
    expect(removed.removedLocal, ['attachments/x.png', 'topics/a.md']);
    expect(removed.held, hasLength(4));
    expect(readRel('.notelore/history/$stamp/topics/a.md'), note);
  });

  test('everything gone from Drive is held, even a single note (#454)', () async {
    write('topics/only.md', note);
    await run();
    drive.files.clear(); // the folder trashed, or the app data deleted
    final report = await run();
    expect(report.held, ['topics/only.md']);
    expect(File(at('topics/only.md')).existsSync(), isTrue);
  });

  test('Restore puts held notes back on Drive in the same pass (#454)', () async {
    for (final name in ['a', 'b']) {
      write('topics/$name.md', note);
    }
    await run();
    drive.files.clear();
    final report = await run(restore: {'topics/a.md', 'topics/b.md'});
    expect(report.pushed, ['topics/a.md', 'topics/b.md']);
    expect(report.held, isEmpty);
    expect(drive.text('topics/a.md'), note);
    expect((await run()).changed, 0);
  });

  test('notes archived on another device are not a mass delete (#454)', () async {
    for (final name in ['a', 'b', 'c', 'd', 'e']) {
      write('topics/$name.md', note);
    }
    await run();
    for (final name in ['a', 'b', 'c', 'd']) {
      drive
        ..files.remove('topics/$name.md')
        ..put('_archive/2026-10-01/topics/$name.md', note);
    }
    final report = await run();
    expect(report.held, isEmpty);
    expect(report.removedLocal, hasLength(4));
    expect(File(at('_archive/2026-10-01/topics/a.md')).existsSync(), isTrue);
  });

  test('emptying the archive on another device is not a mass delete (#454)', () async {
    write('topics/kept.md', note);
    for (final name in ['a', 'b', 'c', 'd']) {
      write('_archive/2026-09-01/topics/$name.md', note);
    }
    await run();
    drive.files.removeWhere((rel, _) => rel.startsWith('_archive/'));
    final report = await run();
    expect(report.held, isEmpty);
    expect(report.removedLocal, hasLength(4));
  });

  test('a few notes gone from many are removed as before (#454)', () async {
    for (var i = 0; i < 10; i++) {
      write('topics/n$i.md', note);
    }
    await run();
    drive.files
      ..remove('topics/n0.md')
      ..remove('topics/n1.md');
    final report = await run();
    expect(report.held, isEmpty);
    expect(report.removedLocal, ['topics/n0.md', 'topics/n1.md']);
  });

  test('another file with other content on Drive is merged, never pulled over (#454)', () async {
    // The notes moved on Drive (new ids) while an older device still edited the
    // old copy: this device's base no longer describes the file there.
    write('topics/t.md', note);
    write('attachments/x.png', 'one');
    await run();
    final edited = '$note- 2026-10-02: from an old device\n';
    drive.files['topics/t.md'] = ('moved-1', utf8.encode(edited));
    drive.files['attachments/x.png'] = ('moved-2', utf8.encode('two'));
    final report = await run(resolve: (conflict) => null);
    expect(report.pulled, isNot(contains('topics/t.md')));
    expect(report.skipped, contains('topics/t.md')); // a conflict, left for the model
    expect(readRel('topics/t.md'), note);
    // An attachment keeps this copy in history and takes Drive's.
    expect(report.history.single, endsWith('attachments/x.png'));
    expect(readRel('attachments/x.png'), 'two');
    // The same content under a new id is just the move: recorded, nothing else.
    drive.files['topics/t.md'] = ('moved-3', utf8.encode(note));
    expect((await run()).changed, 0);
    expect(manifest.get('topics/t.md')!.driveId, 'moved-3');
  });

  test('deleted here but changed there keeps the change', () async {
    write('topics/t.md', note);
    await run();
    File(at('topics/t.md')).deleteSync();
    drive.put('topics/t.md', '$note- [ ] 2026-10-01: still wanted\n');
    expect((await run()).pulled, ['topics/t.md']);
    expect(readRel('topics/t.md'), contains('still wanted'));
  });

  test('identical on both sides without a manifest is just recorded', () async {
    write('topics/t.md', note);
    drive.put('topics/t.md', note);
    expect((await run()).changed, 0);
    expect(drive.uploads, 0);
    expect(manifest.get('topics/t.md'), isNotNull);
  });

  test('remote files that are not notes are left alone', () async {
    drive
      ..put('.notelore/settings.json', '{"language": "tr"}')
      ..put('topics/fine.md', note);
    expect((await run()).pulled, ['topics/fine.md']);
    final again = await run(); // not pulled, so never seen as deleted here
    expect(again.changed, 0);
    expect(drive.trashed, isEmpty);
    expect(drive.text('.notelore/settings.json'), '{"language": "tr"}');
    expect(File(p.join(root, '.notelore', 'settings.json')).existsSync(), isFalse);
  });

  test('unsafe remote paths are ignored', () async {
    drive
      ..put('../escape.md', note)
      ..put('topics/fine.md', note);
    final report = await run();
    expect(report.pulled, ['topics/fine.md']);
    expect(report.ignored, ['../escape.md']);
    expect(File(p.join(p.dirname(root), 'escape.md')).existsSync(), isFalse);
  });

  test('gone on both sides is forgotten', () async {
    write('topics/t.md', note);
    await run();
    File(at('topics/t.md')).deleteSync();
    drive.files.remove('topics/t.md');
    expect((await run()).changed, 0);
    expect(manifest.get('topics/t.md'), isNull);
  });

  test('NFD local names match NFC remote names', () async {
    final nfc = unorm.nfc('topics/café.md');
    write(unorm.nfd(nfc), note);
    drive.put(nfc, note);
    expect((await run()).changed, 0);
    expect(manifest.paths(), [nfc]);
    expect(drive.files.keys, [nfc]);
  });

  test('paths differing only in case are not touched', () async {
    drive
      ..put('topics/A.md', note)
      ..put('topics/a.md', note.replaceAll('one', 'two'));
    expect((await run()).ignored, ['topics/A.md', 'topics/a.md']);
    expect(Directory(at('topics')).existsSync(), isFalse);
  });

  test('a file that is not UTF-8 is skipped, not fatal', () async {
    File(at('topics/latin1.md'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([0x63, 0x61, 0x66, 0xE9, 0x0A]);
    write('topics/fine.md', note);
    drive.files['topics/remote-latin1.md'] = ('r1', [0x63, 0x61, 0x66, 0xE9, 0x0A]);
    final report = await run();
    expect(report.skipped, ['topics/latin1.md', 'topics/remote-latin1.md']);
    expect(report.pushed, ['topics/fine.md']);
  });

  test('a failed upload after a merge changes nothing', () async {
    write('projects/a.md', note);
    await run();
    final local = note.replaceFirst(
      '- 2026-09-01: one\n',
      '- 2026-09-01: one\n- 2026-09-02: laptop\n',
    );
    write('projects/a.md', local);
    drive
      ..put('projects/a.md', '$note- [ ] 2026-09-03: mac\n')
      ..offline = true;
    await expectLater(run(), throwsA(isA<SocketException>()));
    expect(readRel('projects/a.md'), local);
    expect(manifest.base('projects/a.md'), note);
  });

  test('history and archive files sync like notes', () async {
    write('.notelore/history/$stamp/projects/a.local.md', note);
    expect((await run()).pushed, ['.notelore/history/$stamp/projects/a.local.md']);
  });

  test('a missing notes folder and the clock by default', () async {
    drive.put('topics/t.md', note);
    final report = await sync(root, manifest, drive, never);
    expect(report.pulled, ['topics/t.md']);
  });
}
