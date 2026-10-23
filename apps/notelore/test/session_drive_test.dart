import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/session.dart';
import 'package:notelore/src/strings.dart';
import 'package:notelore/src/theme.dart';
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

  group('a Google grant without the hidden folder asks to sign in again (#479)', () {
    test('on a phone: the grant no longer covers both scopes at start', () async {
      final auth = FakeAuth();
      final harness = Harness(auth: auth);
      final first = harness.session();
      await first.connectDrive(); // signed in before, with the old grant
      auth.granted = false; // v0.17.0 asks for drive.appdata too: not granted
      final updated = harness.session();
      await updated.load();
      expect(updated.driveConnected, isFalse);
      expect(updated.driveNeedsSignIn, isTrue); // never a silent no-sync
      await updated.connectDrive();
      expect(updated.driveNeedsSignIn, isFalse);
      expect(updated.driveConnected, isTrue);
    });

    test('on the desktop: a sync refused for its scopes', () async {
      final harness = Harness(auth: FakeAuth());
      final session = harness.session();
      await session.connectDrive();
      expect(session.driveNeedsSignIn, isFalse);
      harness.remote.failure = const NotSignedIn('Request had insufficient authentication scopes.');
      await session.syncNow();
      expect(session.driveNeedsSignIn, isTrue);
      expect(session.driveConnected, isFalse);
    });

    test('a device never signed in, or one that signed out, is not asked', () async {
      final auth = FakeAuth();
      final harness = Harness(auth: auth);
      final fresh = harness.session();
      await fresh.load();
      expect(fresh.driveNeedsSignIn, isFalse);
      await fresh.connectDrive();
      await fresh.disconnectDrive();
      final after = harness.session();
      await after.load();
      expect(after.driveNeedsSignIn, isFalse);
    });

    test('a sync still running when the user disconnects never asks', () async {
      final harness = Harness(auth: FakeAuth());
      final session = harness.session();
      await session.connectDrive();
      harness.remote.hold = Completer();
      final running = session.syncNow();
      await session.disconnectDrive(); // chose to sign out meanwhile
      harness.remote
        ..failure = const NotSignedIn()
        ..hold!.complete();
      await running;
      expect(session.driveNeedsSignIn, isFalse);
    });
  });

  test('connecting Drive signs in and sends the notes up', () async {
    final harness = Harness(auth: FakeAuth());
    final session = harness.session();
    createNote(harness.paths.notes.path, 'topic', 'Mopsos', today: today);
    expect(session.driveAvailable, isTrue);
    await session.connectDrive();
    expect(session.driveConnected, isTrue);
    // The note, and the app settings other devices pick up.
    expect(harness.remote.texts.keys, unorderedEquals(['topics/mopsos.md', sharedSettings]));
    expect(session.syncStatus, 'Synced: 1 sent.');
    await session.syncNow();
    expect(session.syncStatus, 'Synced; nothing changed.');
  });

  test('a sync that moved the notes into hidden storage says so (#454)', () async {
    final harness = Harness(auth: FakeAuth());
    final session = harness.session();
    harness.remote.moved = true;
    await session.connectDrive();
    expect(session.syncStatus, endsWith('no longer holds them; you can delete it.'));
    await session.syncNow(); // said once
    expect(session.syncStatus, 'Synced; nothing changed.');
  });

  group('many notes gone from Drive at once (#454)', () {
    Future<(Session, MemoryRemote, String)> wiped() async {
      final harness = Harness(auth: FakeAuth());
      final session = harness.session();
      final root = harness.paths.notes.path;
      for (final name in ['A', 'B', 'C', 'D']) {
        createNote(root, 'topic', name, today: today);
      }
      await session.connectDrive();
      harness.remote.texts.removeWhere((rel, _) => rel.endsWith('.md'));
      await session.syncNow();
      return (session, harness.remote, root);
    }

    test('are held here, not removed, until the person decides', () async {
      final (session, _, root) = await wiped();
      expect(session.heldNotes, ['topics/a.md', 'topics/b.md', 'topics/c.md', 'topics/d.md']);
      expect(File(p.join(root, 'topics', 'a.md')).existsSync(), isTrue);
      // Named by their titles; one that no longer reads as a note, by its file.
      File(p.join(root, 'topics', 'd.md')).writeAsStringSync('no longer a note');
      expect(session.heldTitles, ['A', 'B', 'C', 'd.md']);
    });

    test('Restore puts them back on Drive', () async {
      final (session, remote, _) = await wiped();
      await session.restoreHeld();
      expect(session.heldNotes, isEmpty);
      expect(remote.texts.keys.where((rel) => rel.endsWith('.md')), hasLength(4));
      await session.syncNow();
      expect(session.heldNotes, isEmpty);
    });

    test('a Restore that failed offline leaves Delete here too working', () async {
      final (session, remote, root) = await wiped();
      remote.failure = const NetworkError('offline');
      await session.restoreHeld();
      expect(session.heldNotes, hasLength(4));
      remote.failure = null;
      await session.deleteHeld();
      expect(File(p.join(root, 'topics', 'a.md')).existsSync(), isFalse);
      expect(remote.texts.keys.where((rel) => rel.endsWith('.md')), isEmpty);
    });

    test('Delete here too moves them to history', () async {
      final (session, _, root) = await wiped();
      await session.deleteHeld();
      expect(session.heldNotes, isEmpty);
      expect(File(p.join(root, 'topics', 'a.md')).existsSync(), isFalse);
      expect(Directory(p.join(root, '.notelore', 'history')).existsSync(), isTrue);
    });
  });

  group('settings travel through Drive', () {
    DateTime Function() at(int hour) =>
        () => DateTime.utc(2026, 10, 12, hour);

    test('the newer change wins: language, provider and model reach the other device', () async {
      final drive = MemoryRemote();
      // Every harness resets the shared test keystore: set the devices up first.
      final laptop = Harness(auth: FakeAuth(), remote: drive).session(clock: at(10));
      final phone = Harness(
        auth: FakeAuth(),
        remote: drive,
      ).session(keySpace: 'phone', clock: at(9));
      final later = Harness(
        auth: FakeAuth()..granted = true,
        remote: drive,
      ).session(keySpace: 'phone', clock: at(11));
      await laptop.connect(findProvider('anthropic'), 'k');
      laptop
        ..setLanguage(AppLanguage.tr)
        ..setPalette(Palette.sunset)
        ..setAppearance(Appearance.dark);
      await laptop.setWebSearch(false);
      await laptop.setModel('model-b');
      await laptop.connectDrive();
      expect(drive.texts[sharedSettings], contains('"language":"tr"'));
      expect(drive.texts[sharedSettings], isNot(contains('"k"'))); // no key ever leaves

      // A phone set up earlier, with its own key for the same provider.
      await phone.connect(findProvider('anthropic'), 'phone-key');
      await phone.connectDrive();
      expect(phone.language, AppLanguage.tr);
      expect(phone.model, 'model-b');
      expect((phone.palette, phone.appearance), (Palette.sunset, Appearance.dark));
      expect(phone.webSearch, isFalse);

      // Later the phone changes the language: the laptop follows on its next sync.
      await later.connect(findProvider('anthropic'), 'phone-key');
      later.setLanguage(AppLanguage.en);
      await later.connectDrive();
      await laptop.syncNow();
      expect(laptop.language, AppLanguage.en);
      await laptop.syncNow(); // nothing new: nothing changes
      expect(laptop.language, AppLanguage.en);
    });

    test('a provider this device has no key for is not switched to', () async {
      final drive = MemoryRemote();
      final laptop = Harness(auth: FakeAuth(), remote: drive).session(clock: at(10));
      final phone = Harness(
        auth: FakeAuth(),
        remote: drive,
      ).session(keySpace: 'phone', clock: at(9));
      await laptop.connect(findProvider('openai'), 'sk');
      laptop.setLanguage(AppLanguage.tr);
      await laptop.connectDrive();
      await phone.connect(findProvider('anthropic'), 'phone-key');
      await phone.connectDrive();
      expect(phone.spec!.name, 'anthropic'); // kept: no OpenAI key here
      expect(phone.language, AppLanguage.tr); // the language still applies
    });

    test('the plan on one device is never an OpenAI key on another (#404)', () async {
      final drive = MemoryRemote();
      final desk = Harness(
        auth: FakeAuth(),
        chatGpt: FakeAuth(),
        remote: drive,
      ).session(clock: at(10));
      final phone = Harness(
        auth: FakeAuth(),
        chatGpt: FakeAuth(), // the plan exists here, signed out
        remote: drive,
      ).session(keySpace: 'phone', clock: at(9));
      await desk.connect(findProvider('chatgpt'), '');
      desk.setLanguage(AppLanguage.tr);
      await desk.connectDrive();
      final shared = jsonDecode(drive.texts[sharedSettings]!) as Map<String, Object?>;
      expect(shared['provider'], 'chatgpt');
      // The newer stamp makes the phone adopt these settings, not the provider.
      await phone.load();
      await phone.connectDrive();
      expect(phone.language, AppLanguage.tr);
      expect(phone.spec, isNull);
      expect([for (final spec in await phone.connections()) spec.name], isNot(contains('openai')));
    });

    test('another device can switch this one to a provider it has a key for', () async {
      final drive = MemoryRemote();
      final desk = Harness(auth: FakeAuth(), remote: drive).session(clock: at(9));
      // The same keystore entries, as on one machine with two windows.
      final other = Harness(auth: FakeAuth(), remote: drive).session(clock: at(10));
      await desk.connect(findProvider('openai'), 'sk'); // a key here for OpenAI too
      await desk.connect(findProvider('anthropic'), 'k');
      await desk.connectDrive();
      await other.connect(findProvider('openai'), 'sk');
      await other.connectDrive();
      await desk.syncNow();
      expect(desk.spec!.name, 'openai');
    });

    test('Ollama is local to each machine, and a damaged settings file is replaced', () async {
      final drive = MemoryRemote();
      drive.texts[sharedSettings] =
          '{"updated": "2026-10-12T12:00:00Z", "provider": "ollama", '
          '"model": "llama3.2"}';
      final phone = Harness(auth: FakeAuth(), remote: drive).session(clock: at(10));
      await phone.connect(findProvider('anthropic'), 'k');
      await phone.connectDrive();
      expect(phone.spec!.name, 'anthropic');
      drive.texts[sharedSettings] = 'not json';
      phone.setLanguage(AppLanguage.tr);
      await phone.syncNow();
      expect(drive.texts[sharedSettings], contains('"language":"tr"'));
    });
  });

  group('Google sign-in comes first (#208)', () {
    test('a build without sign-in never asks for it', () async {
      final session = Harness().session();
      await session.load();
      expect(session.needsGoogle, isFalse);
    });

    test('until this device signs in once; then never again, even signed out', () async {
      final auth = FakeAuth();
      final harness = Harness(auth: auth);
      final first = harness.session();
      await first.load();
      expect(first.needsGoogle, isTrue);
      auth.failSignIn = const SignInFailed('access_denied');
      await expectLater(first.connectDrive(), throwsA(isA<SignInFailed>()));
      expect(first.needsGoogle, isTrue); // no account, no way in
      auth.failSignIn = null;
      await first.connectDrive();
      expect(first.needsGoogle, isFalse);
      // Later, offline or with the grant expired: the app still opens, and its
      // notes with it; Settings connects again.
      auth.granted = false;
      final later = harness.session();
      await later.load();
      expect(later.needsGoogle, isFalse);
      expect(later.driveConnected, isFalse);
    });

    test('a device already connected before this needs no new sign-in', () async {
      final harness = Harness(auth: FakeAuth()..granted = true);
      final session = harness.session();
      await session.load();
      expect(session.needsGoogle, isFalse);
      harness.auth!.granted = false;
      final later = harness.session();
      await later.load();
      expect(later.needsGoogle, isFalse);
    });

    test('a device that synced before this, opened offline, needs no new sign-in', () async {
      final auth = FakeAuth()..granted = true;
      final harness = Harness(auth: auth);
      createNote(harness.paths.notes.path, 'topic', 'Mopsos', today: today);
      final before = harness.session();
      await before.load();
      await before.syncDone;
      // As an older version left it: synced, but no sign-in mark.
      File(p.join(harness.paths.state.path, 'google-signed-in')).deleteSync();
      auth.granted = false; // offline, or the grant expired
      final later = harness.session();
      await later.load();
      expect(later.needsGoogle, isFalse);
    });

    test('disconnecting is signing out: the next start asks again', () async {
      final harness = Harness(auth: FakeAuth()..granted = true);
      final session = harness.session();
      await session.load();
      await session.syncDone;
      await session.disconnectDrive();
      expect(session.needsGoogle, isTrue);
      final later = harness.session();
      await later.load();
      expect(later.needsGoogle, isTrue);
    });
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
          {
            'type': 'tool_use',
            'id': 't2',
            'name': 'add_note_entry',
            'input': {'slug': 'mopsos', 'text': 'Started.'},
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
    expect(harness.remote.texts.keys, unorderedEquals(['projects/mopsos.md', sharedSettings]));
  });

  test('a note deleted for good from the archive goes to Drive\'s trash (#438)', () async {
    final harness = Harness(auth: FakeAuth()..granted = true);
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'k');
    await session.load();
    createNote(harness.paths.notes.path, 'topic', 'Kitaplar', today: today);
    await session.deleteNote(session.listNotes().single);
    await session.syncNow();
    expect(harness.remote.texts.keys.where((k) => k.startsWith('_archive/')), hasLength(1));
    await session.deleteArchived(session.listArchived().single);
    await session.syncDone;
    expect(harness.remote.texts.keys.where((k) => k.startsWith('_archive/')), isEmpty);
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

  test("a Drive error is said in plain words, never Google's own (#480)", () async {
    final harness = Harness(auth: FakeAuth()..granted = true);
    harness.remote.failure = const HttpError(
      403,
      'The user has exceeded their Drive storage quota',
    );
    final session = harness.session();
    await session.load();
    await session.syncDone;
    expect(
      session.syncStatus,
      'Your Google Drive is full: free some space and Notelore syncs again.',
    );
    // A rate limit is not a full Drive: telling that to delete things would be wrong.
    harness.remote.failure = const HttpError(403, 'User rate limit exceeded: project quota');
    await session.syncNow();
    expect(session.syncStatus, 'Google Drive could not be reached. Notelore tries again later.');
    harness.remote.failure = const HttpError(500, 'Backend Error');
    await session.syncNow();
    expect(session.syncStatus, 'Google Drive could not be reached. Notelore tries again later.');
    // Refused even after a fresh token: a sign-in again, not a wait.
    harness.remote.failure = const HttpError(401, 'Invalid Credentials');
    await session.syncNow();
    expect(session.syncStatus, 'Signed out of Google. Connect again.');
    expect(session.driveNeedsSignIn, isTrue);
    harness.remote.failure = null;
    await session.connectDrive();
    harness.remote.failure = const HttpError(500, 'Backend Error');
    session.setLanguage(AppLanguage.tr);
    await session.syncNow();
    expect(session.syncStatus, "Google Drive'a ulaşılamadı. Notelore daha sonra yeniden dener.");
    harness.remote.failure = const MissingDriveGrant(
      'The granted scopes do not give access to all of the requested spaces.',
    );
    await session.syncNow();
    expect(
      session.syncStatus,
      "Notlarının eşitlenmeye devam etmesi için Google'a yeniden giriş yap.",
    );
    expect(session.syncStatus, isNot(contains('scopes')));
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
    expect(session.syncStatus, 'Signed out of Google. Connect again.');
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
