import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notelore_core/src/providers/http.dart';
import 'package:notelore_core/src/store/notes.dart';
import 'package:notelore_core/src/sync/drive.dart';
import 'package:notelore_core/src/sync/engine.dart';
import 'package:notelore_core/src/sync/manifest.dart';
import 'package:notelore_core/src/sync/merge.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/files.dart';
import 'fake_drive.dart';

final today = DateTime.utc(2026, 10, 1);

void main() {
  late FakeDrive drive;
  late List<bool> refreshes;
  late String issued; // the token the client holds
  late bool refreshWorks;
  setUp(() {
    drive = FakeDrive();
    refreshes = [];
    issued = drive.token;
    refreshWorks = true;
  });

  DriveRemote remote() => DriveRemote(drive.client, ({bool refresh = false}) async {
    refreshes.add(refresh);
    if (refresh && refreshWorks) issued = drive.token;
    return issued;
  });

  test('an empty Drive lists nothing and creates nothing', () async {
    expect(await remote().list(), isEmpty);
    expect(drive.files, isEmpty);
  });

  test('upload creates the Notelore folder tree, then lists and downloads', () async {
    final r = remote();
    await r.list();
    final created = await r.upload('projects/a.md', utf8.encode('# A\n'), null);
    await r.upload('projects/b.md', utf8.encode('# B\n'), null); // the folder is reused
    await r.upload('_archive/2026-01-01/topics/c.md', utf8.encode('# C\n'), null);
    expect(drive.text('projects/a.md'), '# A\n');
    expect(drive.text('_archive/2026-01-01/topics/c.md'), '# C\n');
    final folders = drive.files.values.where((f) => '${f['mimeType']}'.endsWith('folder'));
    expect(
      folders.map((f) => f['name']),
      unorderedEquals(['Notelore', 'projects', '_archive', '2026-01-01', 'topics']),
    );
    final listed = await remote().list(); // a fresh client finds it all again
    expect(
      listed.keys,
      unorderedEquals(['projects/a.md', 'projects/b.md', '_archive/2026-01-01/topics/c.md']),
    );
    expect(listed['projects/a.md']!.id, created.id);
    expect(listed['projects/a.md']!.md5, created.md5);
    expect(utf8.decode(await r.download(created.id)), '# A\n');
  });

  test('a replaced file keeps its id and gets a new md5', () async {
    final r = remote();
    final first = await r.upload('topics/t.md', utf8.encode('one\n'), null);
    final second = await r.upload('topics/t.md', utf8.encode('two\n'), first.id);
    expect(second.id, first.id);
    expect(second.md5, isNot(first.md5));
    expect(second.modified, isNot(first.modified));
    expect(drive.text('topics/t.md'), 'two\n');
  });

  test('trash moves the file out of the listing', () async {
    final r = remote();
    final file = await r.upload('topics/t.md', utf8.encode('x\n'), null);
    await r.trash(file.id);
    expect(await remote().list(), isEmpty);
    expect(drive.files[file.id]!['trashed'], isTrue); // reversible, not deleted
  });

  test('files outside the Notelore folder, folders and Google Docs are not notes', () async {
    final r = remote();
    await r.upload('topics/t.md', utf8.encode('x\n'), null);
    final root = drive.files.values.firstWhere((f) => f['name'] == 'Notelore')['id']! as String;
    drive
      ..add('elsewhere.md', 'some-other-folder', text: 'not ours')
      ..add('doc', root)
      ..add('empty-folder', root, folder: true);
    expect((await remote().list()).keys, ['topics/t.md']);
  });

  test('listing follows every page', () async {
    final r = remote();
    for (final name in ['a', 'b', 'c']) {
      await r.upload('topics/$name.md', utf8.encode('$name\n'), null);
    }
    drive.pageSize = 2;
    expect(
      (await remote().list()).keys,
      unorderedEquals(['topics/a.md', 'topics/b.md', 'topics/c.md']),
    );
  });

  test('an expired token is refreshed once', () async {
    final r = remote();
    drive.token = 'token-2'; // the cached token-1 no longer works
    expect(await r.list(), isEmpty);
    expect(refreshes, [false, true]);
    drive.token = 'token-3';
    refreshWorks = false; // refreshing does not help: the error surfaces
    await expectLater(r.list(), throwsA(isA<HttpError>().having((e) => e.status, 'status', 401)));
  });

  test('offline is a NetworkError, an API failure an HttpError', () async {
    final r = remote();
    drive.offline = true;
    await expectLater(r.list(), throwsA(isA<NetworkError>()));
    drive.offline = false;
    await expectLater(
      r.download('missing'),
      throwsA(isA<HttpError>().having((e) => e.message, 'message', contains('File not found'))),
    );
  });

  test('a Drive that does not answer in time is offline', () async {
    final hanging = DriveRemote(
      MockClient((_) => Completer<http.Response>().future),
      ({bool refresh = false}) async => 't',
      timeout: const Duration(milliseconds: 10),
    );
    await expectLater(hanging.list(), throwsA(isA<NetworkError>()));
  });

  test('two folders named Notelore: the first one created wins', () async {
    final r = remote();
    await r.upload('topics/t.md', utf8.encode('first\n'), null);
    final other = drive.add('Notelore', 'root', folder: true);
    other['appProperties'] = {'notelore': 'root'};
    drive.add('topics', other['id']! as String, folder: true);
    expect((await remote().list()).keys, ['topics/t.md']);
  });

  group('two devices syncing through one Drive', () {
    late String laptop;
    late String phone;
    late Manifest laptopManifest;
    late Manifest phoneManifest;
    setUp(() {
      final dir = tempDir();
      laptop = p.join(dir, 'laptop');
      phone = p.join(dir, 'phone');
      laptopManifest = Manifest(p.join(dir, 'laptop-state'));
      phoneManifest = Manifest(p.join(dir, 'phone-state'));
    });

    List<String>? never(Conflict conflict) => fail('no model needed');

    test('a note made on one device appears on the other, and edits merge', () async {
      final note = createNote(laptop, 'project', 'Mopsos', today: today);
      addEntry(note, 'From the laptop.', today: today);
      expect((await sync(laptop, laptopManifest, remote(), never)).pushed, ['projects/mopsos.md']);
      expect((await sync(phone, phoneManifest, remote(), never)).pulled, ['projects/mopsos.md']);
      final onPhone = p.join(phone, 'projects', 'mopsos.md');
      expect(File(onPhone).readAsStringSync(), File(note).readAsStringSync());

      addEntry(note, 'Laptop again.', today: DateTime.utc(2026, 10, 2));
      addTodo(onPhone, 'From the phone', today: DateTime.utc(2026, 10, 3));
      await sync(laptop, laptopManifest, remote(), never);
      final report = await sync(phone, phoneManifest, remote(), never);
      expect(report.merged, ['projects/mopsos.md']);
      await sync(laptop, laptopManifest, remote(), never);
      final merged = File(note).readAsStringSync();
      expect(merged, File(onPhone).readAsStringSync());
      expect(
        merged,
        allOf(
          contains('Laptop again.'),
          contains('From the phone'),
          contains('updated: 2026-10-03'),
        ),
      );
    });

    test('archiving on one device moves the note away on the other', () async {
      final note = createNote(laptop, 'topic', 'Old', today: today);
      await sync(laptop, laptopManifest, remote(), never);
      await sync(phone, phoneManifest, remote(), never);
      archiveNote(laptop, note, today: today);
      final pushed = await sync(laptop, laptopManifest, remote(), never);
      expect(pushed.removedRemote, ['topics/old.md']);
      final pulled = await sync(phone, phoneManifest, remote(), never);
      expect(pulled.pulled, ['_archive/2026-10-01/topics/old.md']);
      expect(pulled.removedLocal, ['topics/old.md']);
      expect(File(p.join(phone, 'topics', 'old.md')).existsSync(), isFalse);
    });
  });
}
