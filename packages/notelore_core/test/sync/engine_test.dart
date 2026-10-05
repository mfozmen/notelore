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
  var _next = 0;

  void put(String rel, String text) => files[rel] = (files[rel]?.$1 ?? _newId(), utf8.encode(text));

  String _newId() => 'id${++_next}';

  String text(String rel) => utf8.decode(files[rel]!.$2);

  RemoteFile _meta(String rel) {
    final (id, data) = files[rel]!;
    return RemoteFile(id: id, md5: md5.convert(data).toString(), modified: 't${data.length}');
  }

  @override
  Future<Map<String, RemoteFile>> list() async => {for (final rel in files.keys) rel: _meta(rel)};

  @override
  Future<List<int>> download(String fileId) async =>
      files.values.firstWhere((file) => file.$1 == fileId).$2;

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
  Future<SyncReport> run([Resolver resolve = never]) =>
      sync(root, manifest, drive, resolve, now: now);

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

  test('a real conflict asks the resolver and keeps both sides', () async {
    write('projects/a.md', note);
    await run();
    write('projects/a.md', note.replaceAll('one', 'laptop wording'));
    drive.put('projects/a.md', note.replaceAll('one', 'mac wording'));
    final asked = <Conflict>[];
    final report = await run((conflict) async {
      asked.add(conflict);
      return conflict.remote;
    });
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
    final report = await run((conflict) => null);
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
    await run();
    drive.files.remove('topics/t.md');
    final report = await run();
    expect(report.removedLocal, ['topics/t.md']);
    expect(File(at('topics/t.md')).existsSync(), isFalse);
    expect(readRel('.notelore/history/$stamp/topics/t.md'), note);
    expect(report.history, ['.notelore/history/$stamp/topics/t.md']);
    expect(manifest.get('topics/t.md'), isNull);
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
