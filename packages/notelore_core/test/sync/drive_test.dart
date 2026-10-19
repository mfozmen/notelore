import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notelore_core/src/oauth.dart';
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

  var now = DateTime.utc(2026, 10, 19, 12);
  setUp(() => now = DateTime.utc(2026, 10, 19, 12));

  DriveRemote remote() => DriveRemote(drive.client, ({bool refresh = false}) async {
    refreshes.add(refresh);
    if (refresh && refreshWorks) issued = drive.token;
    return issued;
  }, clock: () => now);

  test('an empty Drive lists nothing and creates nothing', () async {
    expect(await remote().list(), isEmpty);
    expect(drive.files, isEmpty);
  });

  test("files go into Drive's hidden app folder, named by their path (#454)", () async {
    final r = remote();
    await r.list();
    final created = await r.upload('projects/a.md', utf8.encode('# A\n'), null);
    await r.upload('_archive/2026-01-01/topics/c.md', utf8.encode('# C\n'), null);
    expect(drive.text('projects/a.md'), '# A\n');
    expect(drive.file('projects/a.md')!['parents'], ['appDataFolder']);
    expect(drive.text('_archive/2026-01-01/topics/c.md'), '# C\n');
    expect(drive.files.values.where((f) => '${f['mimeType']}'.endsWith('folder')), isEmpty);
    final listed = await remote().list(); // a fresh client finds it all again
    expect(listed.keys, unorderedEquals(['projects/a.md', '_archive/2026-01-01/topics/c.md']));
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

  test('a removal is marked, not deleted, and goes for good after 30 days (#454)', () async {
    // Drive cannot trash a file in the app folder: the mark stands in for its trash.
    final r = remote();
    final file = await r.upload('topics/t.md', utf8.encode('x\n'), null);
    await r.trash(file.id);
    expect(await remote().list(), isEmpty);
    expect(drive.files[file.id]!['appProperties'], {'removed': '2026-10-19T12:00:00.000Z'});
    now = now.add(const Duration(days: 30));
    expect(await remote().list(), isEmpty);
    expect(drive.files, contains(file.id)); // 30 days to the minute: still kept
    now = now.add(const Duration(minutes: 1));
    expect(await remote().list(), isEmpty);
    expect(drive.files, isNot(contains(file.id)));
  });

  test("the 30 days count by Drive's clock, never by a device's that is off", () async {
    final r = remote();
    final file = await r.upload('topics/t.md', utf8.encode('x\n'), null);
    drive.now = DateTime.utc(2026, 10, 1);
    await r.trash(file.id); // marked when Drive says it is
    now = DateTime.utc(2027, 3, 1); // months ahead
    drive.now = DateTime.utc(2026, 10, 2);
    expect(await remote().list(), isEmpty);
    expect(drive.files, contains(file.id));
  });

  test('a mark that does not read as a time counts from now', () async {
    final file = drive.add('topics/t.md', 'appDataFolder', text: 'x\n')
      ..['appProperties'] = {'removed': 'yes'};
    expect(await remote().list(), isEmpty);
    expect(drive.files[file['id']]!['appProperties'], {'removed': '2026-10-19T12:00:00.000Z'});
  });

  test('a file another device removed meanwhile is no error; a Drive failure is', () async {
    final old = drive.add('topics/a.md', 'appDataFolder', text: 'a\n')
      ..['appProperties'] = {'removed': '2026-01-01T00:00:00Z'};
    drive.gone.add(old['id']! as String);
    expect(await remote().list(), isEmpty);
    drive
      ..gone.clear()
      ..failing.add(old['id']! as String);
    await expectLater(
      remote().list(),
      throwsA(isA<HttpError>().having((e) => e.status, 'status', 500)),
    );
  });

  test('only the app folder holds notes: My Drive and Google Docs are not notes', () async {
    final r = remote();
    await r.upload('topics/t.md', utf8.encode('x\n'), null);
    drive
      ..add('elsewhere.md', 'some-other-folder', text: 'not ours')
      ..add('doc', 'appDataFolder');
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
    expect(refreshes.take(2), [false, true]);
    drive.token = 'token-3';
    refreshWorks = false; // refreshing does not help: the error surfaces
    await expectLater(r.list(), throwsA(isA<HttpError>().having((e) => e.status, 'status', 401)));
  });

  test('a grant from before the app folder asks to sign in again (#454)', () async {
    drive.appData = false;
    await expectLater(remote().list(), throwsA(isA<NotSignedIn>()));
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

  group('the visible Notelore folder moves into the app folder once (#454)', () {
    test('its files are copied and go to the trash; the folder stays, marked', () async {
      final root = drive.legacy({
        'projects/a.md': '# A\n',
        '_archive/2026-01-01/topics/c.md': '# C\n',
        '.notelore/settings.json': '{}',
      });
      // A Google Doc put there by hand: not Notelore's to copy or throw away.
      final doc = drive.add('doc', root['id']! as String);
      final r = remote();
      final listed = await r.list();
      expect(
        listed.keys,
        unorderedEquals([
          'projects/a.md',
          '_archive/2026-01-01/topics/c.md',
          '.notelore/settings.json',
        ]),
      );
      expect(drive.text('projects/a.md'), '# A\n');
      expect(drive.file('doc'), isNull);
      final old = drive.files.values.where((f) => f['name'] == 'a.md').single;
      expect(old['trashed'], isTrue); // reversible: in Drive's trash for 30 days
      expect(doc['trashed'], isFalse);
      expect(root['trashed'], isFalse);
      expect(root['appProperties'], {'notelore': 'moved'});
      expect(r.moved, isTrue);
      await r.list();
      expect(r.moved, isTrue); // for the app to say once, however often it lists
      final again = remote();
      expect((await again.list()).keys, hasLength(3));
      expect(again.moved, isFalse);
    });

    test('a file another device moved meanwhile is skipped', () async {
      drive.legacy({'topics/a.md': 'a\n', 'topics/b.md': 'b\n'});
      final b = drive.files.values.firstWhere((f) => f['name'] == 'b.md');
      drive.gone.add(b['id']! as String);
      expect((await remote().list()).keys, ['topics/a.md']);
    });

    test('a move cut off, or made by two devices at once, keeps one copy of each', () async {
      drive.legacy({'topics/a.md': 'a\n', 'topics/b.md': 'b\n'});
      // Another device copied "a" already, and so did this one before either trashed.
      final older = drive.add('topics/a.md', 'appDataFolder', text: 'a\n');
      final newer = drive.add('topics/a.md', 'appDataFolder', text: 'a\n');
      final listed = await remote().list();
      expect(listed.keys, unorderedEquals(['topics/a.md', 'topics/b.md']));
      expect(listed['topics/a.md']!.id, older['id']); // the first one made wins
      expect((newer['appProperties']! as Map)['removed'], isNotNull); // the other marked
      expect(drive.files.values.where((f) => f['name'] == 'topics/b.md'), hasLength(1));
    });

    test('two folders named Notelore: the first one created is moved', () async {
      drive
        ..legacy({'topics/t.md': 'first\n'})
        ..legacy({'topics/t.md': 'second\n'});
      expect((await remote().list()).keys, ['topics/t.md']);
      expect(drive.text('topics/t.md'), 'first\n');
    });
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
