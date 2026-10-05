import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/session.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

const note =
    '---\ntitle: T\nkind: topic\ncreated: 2026-09-01\nupdated: 2026-09-01\n---\n# T\n\n## Notes\n- 2026-09-01: one\n';

void main() {
  autoSyncTests();
  test('a build without Drive sign-in has no sync', () async {
    final session = Harness().session();
    await session.load();
    expect(session.driveAvailable, isFalse);
    expect(session.driveConnected, isFalse);
    await session.syncNow(); // nothing to do, nothing thrown
    expect(session.syncStatus, isNull);
  });

  test('the real remote is Google Drive', () {
    final harness = Harness();
    final session = Session(harness.paths);
    addTearDown(session.dispose);
    expect(session.remoteFor(FakeAuth()), isA<DriveRemote>());
  });

  test('connecting Drive signs in and sends the notes up', () async {
    final harness = Harness(auth: FakeAuth());
    final session = harness.session();
    createNote(harness.paths.notes.path, 'topic', 'Mopsos', today: today);
    expect(session.driveAvailable, isTrue);
    await session.connectDrive();
    expect(session.driveConnected, isTrue);
    expect(harness.remote.texts.keys, ['topics/mopsos.md']);
    expect(session.syncStatus, 'Synced: 1 sent.');
    await session.syncNow();
    expect(session.syncStatus, 'Synced; nothing changed.');
  });

  test('a failed sign-in leaves Drive disconnected', () async {
    final harness = Harness(auth: FakeAuth()..failSignIn = const SignInFailed('access_denied'));
    final session = harness.session();
    await expectLater(session.connectDrive(), throwsA(isA<SignInFailed>()));
    expect(session.driveConnected, isFalse);
  });

  test('a signed-in device syncs on start and pulls what other devices wrote', () async {
    final harness = Harness(auth: FakeAuth()..granted = true);
    harness.remote.texts['topics/t.md'] = note;
    final session = harness.session();
    await session.load();
    await session.syncDone;
    expect(session.driveConnected, isTrue);
    expect(File(p.join(harness.paths.notes.path, 'topics', 't.md')).readAsStringSync(), note);
    expect(session.syncStatus, 'Synced: 1 received.');
  });

  test('every chat turn is followed by a sync', () async {
    final harness = Harness(
      auth: FakeAuth()..granted = true,
      answers: [
        const AgentResponse([
          {
            'type': 'tool_use',
            'id': 't1',
            'name': 'create_note',
            'input': {'kind': 'project', 'title': 'Mopsos'},
          },
        ], 'tool_use'),
        'Created.',
      ],
    );
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    await session.load();
    await session.send('Mopsos diye proje aç');
    await session.syncDone;
    expect(harness.remote.texts.keys, ['projects/mopsos.md']);
  });

  test('offline is not an error: the next sync catches up', () async {
    final harness = Harness(auth: FakeAuth()..granted = true);
    harness.remote.failure = const NetworkError('no route to host');
    final session = harness.session();
    await session.load();
    await session.syncDone;
    expect(session.driveConnected, isTrue);
    expect(session.syncStatus, 'Offline; your notes will sync when the connection is back.');
    harness.remote.failure = null;
    await session.syncNow();
    expect(session.syncStatus, startsWith('Synced'));
  });

  test('a Drive error is shown as it is', () async {
    final harness = Harness(auth: FakeAuth()..granted = true);
    harness.remote.failure = const HttpError(
      403,
      'The user has exceeded their Drive storage quota',
    );
    final session = harness.session();
    await session.load();
    await session.syncDone;
    expect(session.syncStatus, 'Google Drive: The user has exceeded their Drive storage quota');
  });

  test('a note another program holds is retried on the next sync', () async {
    final harness = Harness(auth: FakeAuth()..granted = true);
    harness.remote.failure = const FileSystemException('Cannot rename file', 'topics/t.md');
    final session = harness.session();
    await session.load();
    await session.syncDone;
    expect(session.driveConnected, isTrue);
    expect(
      session.syncStatus,
      'A note is in use by another program (Cannot rename file); the next sync retries.',
    );
  });

  test('revoked access disconnects and asks to connect again', () async {
    final harness = Harness(auth: FakeAuth()..granted = true);
    harness.remote.failure = const NotSignedIn('Google Drive access was revoked or expired');
    final session = harness.session();
    await session.load();
    await session.syncDone;
    expect(session.driveConnected, isFalse);
    expect(session.syncStatus, 'Google Drive access was revoked or expired; connect again.');
  });

  test('a same-line conflict goes to the model, and its reason is reported', () async {
    final harness = Harness(
      auth: FakeAuth()..granted = true,
      answers: ['<merged>\n- 2026-09-01: one, merged\n</merged><why>Kept both wordings.</why>'],
    );
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    final local = File(p.join(harness.paths.notes.path, 'topics', 't.md'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(note);
    await session.connectDrive(); // the shared starting point
    local.writeAsStringSync(note.replaceAll('one', 'one, laptop'));
    harness.remote.texts['topics/t.md'] = note.replaceAll('one', 'one, phone');
    await session.syncNow();
    expect(local.readAsStringSync(), contains('one, merged'));
    expect(session.syncStatus, 'Synced: 1 merged. Kept both wordings.');
  });

  test('an unsettled conflict waits for the next sync', () async {
    final harness = Harness(auth: FakeAuth()..granted = true);
    final session = harness.session(); // no provider connected: nobody to settle it
    final local = File(p.join(harness.paths.notes.path, 'topics', 't.md'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(note);
    await session.connectDrive();
    local.writeAsStringSync(note.replaceAll('one', 'one, laptop'));
    harness.remote.texts['topics/t.md'] = note.replaceAll('one', 'one, phone');
    await session.syncNow();
    expect(session.syncStatus, 'Synced: 1 waiting for a conflict to be settled.');
  });

  test('disconnecting signs out of Drive; the notes stay', () async {
    final auth = FakeAuth()..granted = true;
    final harness = Harness(auth: auth);
    final session = harness.session();
    createNote(harness.paths.notes.path, 'topic', 'Mopsos', today: today);
    await session.load();
    await session.syncDone;
    await session.disconnectDrive();
    expect(auth.signedOut, isTrue);
    expect(session.driveConnected, isFalse);
    expect(session.syncStatus, isNull);
    expect(session.listNotes(), hasLength(1));
  });

  test('syncs and chat turns never overlap', () async {
    final harness = Harness(auth: FakeAuth()..granted = true, answers: ['ok']);
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    await session.connectDrive();
    final order = <String>[];
    final first = session.syncNow().then((_) => order.add('sync'));
    final second = session.send('hi').then((_) => order.add('send'));
    expect(session.syncing, isTrue);
    await Future.wait([first, second]);
    expect(order, ['sync', 'send']);
    await session.syncDone; // the sync after the turn
  });

  test('a sync that ends after the session closed does not notify', () async {
    final harness = Harness(auth: FakeAuth()..granted = true);
    final session = harness.session(owned: false);
    await session.load(); // starts a sync in the background
    session.dispose();
    await session.syncDone;
  });
}

void autoSyncTests() {
  // Real time with short ticks: the session's futures run on the real clock.
  // Waiting polls until a deadline, so a slow runner only makes it slower.
  const every = Duration(milliseconds: 20);
  const remoteNote = 'REMOTE';

  Future<bool> appears(File file) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      if (file.existsSync()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return false;
  }

  Future<void> ticks([int count = 10]) => Future<void>.delayed(every * count);

  test("while the app is open it pulls other devices' notes on its own", () async {
    final harness = Harness(auth: FakeAuth()..granted = true);
    final session = harness.session();
    await session.load();
    await session.syncDone;
    session.startAutoSync(every: every);
    harness.remote.texts['topics/r.md'] = remoteNote; // written on another device
    expect(await appears(File(p.join(harness.paths.notes.path, 'topics', 'r.md'))), isTrue);
    session.stopAutoSync();
  });

  test('no automatic sync while disconnected, busy or closed', () async {
    final harness = Harness(auth: FakeAuth());
    final session = harness.session(owned: false);
    session.startAutoSync(every: every);
    await ticks();
    expect(session.syncStatus, isNull); // not connected: nothing ran
    await session.connectDrive();
    session.busy = true; // a chat turn is running
    harness.remote.texts['topics/s.md'] = remoteNote;
    await ticks();
    await session.syncDone;
    final pulled = File(p.join(harness.paths.notes.path, 'topics', 's.md'));
    expect(pulled.existsSync(), isFalse);
    session
      ..busy = false
      ..dispose(); // stops the timer too
    await ticks();
    expect(pulled.existsSync(), isFalse); // no tick after dispose
  });

  test('a second sync queued behind a running one still counts as syncing', () async {
    final harness = Harness(auth: FakeAuth());
    final session = harness.session();
    await session.connectDrive();
    harness.remote.hold = Completer<void>();
    final first = session.syncNow();
    final second = session.syncNow();
    harness.remote.hold!.complete();
    await first;
    expect(session.syncing, isTrue); // the second one is still pending
    await second;
    expect(session.syncing, isFalse);
  });
}
