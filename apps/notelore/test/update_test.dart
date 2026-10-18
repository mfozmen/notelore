import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notelore/src/update.dart';
import 'package:path/path.dart' as p;

const v = '9.9.9';

/// The test release key: a fixed seed, and the public key it gives (#312).
final testSeed = List.filled(32, 7);
const testPublicKey = '6kpsY+KcUgq+9VB7Ey7F+ZVHdq6+vnuSQh7qaRRG0iw=';

/// A GitHub "latest release" answer with the app assets for [version], each
/// with its checksum and its signature unless told otherwise.
List<int> release(String version, {bool checksums = true, bool signatures = true}) {
  final apps = [
    'notelore-app-$version-windows-x64-setup.exe',
    'notelore-app-$version-macos.dmg',
    'notelore-app-$version-android.apk',
  ];
  final names = [
    ...apps,
    if (checksums) ...apps.map((a) => '$a.sha256'),
    if (signatures) ...apps.map((a) => '$a.sig'),
  ];
  return utf8.encode(
    jsonEncode({
      'tag_name': 'v$version',
      'assets': [
        for (final n in names) {'name': n, 'browser_download_url': 'https://dl/$n'},
      ],
    }),
  );
}

/// Fetches from a map of URL -> bytes; anything else is "offline". A `.sig`
/// the map does not hold is the test key's signature of the file it names, as
/// the release workflow makes it (#312).
class Pages {
  Pages(this.pages);

  final Map<String, List<int>> pages;
  var calls = 0;

  Future<List<int>> call(String url) async {
    calls++;
    final page = pages[url];
    if (page != null) return page;
    final signed = url.endsWith('.sig') ? pages[url.substring(0, url.length - 4)] : null;
    if (signed == null) throw UpdateFailed('offline: $url');
    final key = await Ed25519().newKeyPairFromSeed(testSeed);
    return (await Ed25519().sign(signed, keyPair: key)).bytes;
  }
}

/// The zip download and its sha256sum line.
Map<String, List<int>> download(String name, List<int> zip, {String? digest}) => {
  'https://dl/$name': zip,
  'https://dl/$name.sha256': utf8.encode('${digest ?? sha256.convert(zip)}  $name\n'),
};

void write(String path, String text) => File(path)
  ..parent.createSync(recursive: true)
  ..writeAsStringSync(text);

String read(String path) => File(path).readAsStringSync();

void main() {
  transportTests();
  late String dir;
  setUp(() {
    final temp = Directory.systemTemp.createTempSync('notelore_update_');
    addTearDown(() => temp.deleteSync(recursive: true));
    dir = temp.path;
  });

  test('isNewer compares numerically; anything odd is not newer', () {
    expect(isNewer('0.10.0', '0.9.1'), isTrue);
    expect(isNewer('0.9.1', '0.9.1'), isFalse);
    expect(isNewer('1.0.0', '1.0'), isTrue);
    expect(isNewer('1.0.0-rc.1', '0.9.0'), isFalse);
    expect(isNewer('1.0.0', 'dev'), isFalse);
  });

  test('asset names follow release.yml', () {
    expect(assetName('1.2.3', 'windows'), 'notelore-app-1.2.3-windows-x64-setup.exe');
    expect(assetName('1.2.3', 'macos'), 'notelore-app-1.2.3-macos.dmg');
    expect(assetName('1.2.3', 'android'), 'notelore-app-1.2.3-android.apk');
    expect(() => assetName('1.2.3', 'linux'), throwsA(isA<UpdateFailed>()));
  });

  group('the check', () {
    test('asks GitHub every time, so each start hears of a new release', () async {
      final pages = Pages({latestReleaseUrl: release('0.2.0')});
      expect(await checkForUpdate(current: '0.2.0', fetch: pages.call), isNull);
      pages.pages[latestReleaseUrl] = release(v); // published a minute later
      expect(await checkForUpdate(current: '0.2.0', fetch: pages.call), v);
      expect(await checkForUpdate(current: v, fetch: pages.call), isNull);
      expect(pages.calls, 3);
    });

    test('offline or a garbled answer is silent, unless forced', () async {
      expect(await checkForUpdate(current: '0.2.0', fetch: Pages({}).call), isNull);
      final garbled = Pages({latestReleaseUrl: utf8.encode('<html>')});
      expect(await checkForUpdate(current: '0.2.0', fetch: garbled.call), isNull);
      await expectLater(
        checkForUpdate(current: '0.2.0', fetch: Pages({}).call, force: true),
        throwsA(isA<UpdateFailed>()),
      );
    });
  });

  group('Windows: the installer', () {
    late String install;
    late List<List<String>> spawned;
    setUp(() {
      install = p.join(dir, 'Notelore');
      write(p.join(install, 'notelore.exe'), 'old exe');
      spawned = [];
    });

    Updater updater(Map<String, List<int>> pages, {Spawn? spawn}) => Updater(
      system: 'windows',
      executable: p.join(install, 'notelore.exe'),
      current: '0.2.0',
      temp: Directory(p.join(dir, 'temp'))..createSync(recursive: true),
      publicKey: base64Decode(testPublicKey),
      fetch: Pages(pages).call,
      run: (command, args) async => fail('nothing is unpacked on Windows'),
      spawn: spawn ?? (exe, args) async => spawned.add([exe, ...args]),
    );

    final setup = utf8.encode('setup bytes');
    Map<String, List<int>> good() => {
      latestReleaseUrl: release(v),
      ...download('notelore-app-$v-windows-x64-setup.exe', setup),
    };

    test('download and verify the setup, then run it silently into this folder', () async {
      final u = updater(good());
      expect(await u.apply(), v);
      expect(read(p.join(install, 'notelore.exe')), 'old exe'); // the setup replaces it
      await u.relaunch();
      final [exe, ...args] = spawned.single;
      expect(File(exe).readAsBytesSync(), setup);
      expect(p.basename(exe), 'notelore-app-$v-windows-x64-setup.exe');
      expect(args, ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/DIR=$install']);
    });

    test('the download stays in its own temp folder, safe from another cleanup (#330)', () async {
      final u = updater(good());
      expect(await u.apply(), v);
      // Another updater (another test file run in parallel, or another start)
      // cleaning up its temp folder leaves this download alone.
      Updater(
        system: 'windows',
        executable: p.join(install, 'notelore.exe'),
        current: '0.2.0',
        temp: Directory(p.join(dir, 'other-temp'))..createSync(),
        publicKey: base64Decode(testPublicKey),
        fetch: Pages(const {}).call,
        run: (command, args) async => fail('nothing runs'),
        spawn: (exe, args) async => fail('nothing starts'),
      ).cleanup();
      await u.relaunch();
      final [exe, ...] = spawned.single;
      expect(p.isWithin(p.join(dir, 'temp'), exe), isTrue);
      expect(File(exe).readAsBytesSync(), setup);
    });

    test('already up to date: nothing is downloaded', () async {
      expect(await updater({latestReleaseUrl: release('0.2.0')}).apply(), isNull);
    });

    test('a bad checksum, a missing checksum or a missing asset installs nothing', () async {
      final wrong = {
        latestReleaseUrl: release(v),
        ...download('notelore-app-$v-windows-x64-setup.exe', setup, digest: 'f' * 64),
      };
      final cases = {
        'checksum mismatch': wrong,
        'publishes no checksum': {latestReleaseUrl: release(v, checksums: false)},
        // #312: a checksum from the same release proves nothing on its own.
        'publishes no signature': {...good(), latestReleaseUrl: release(v, signatures: false)},
        'signature does not match': {
          ...good(),
          'https://dl/notelore-app-$v-windows-x64-setup.exe.sig': List.filled(64, 1),
        },
        'has no notelore-app': {
          latestReleaseUrl: utf8.encode(jsonEncode({'tag_name': 'v$v', 'assets': <Object>[]})),
        },
        'is empty': {...good(), 'https://dl/notelore-app-$v-windows-x64-setup.exe.sha256': <int>[]},
      };
      for (final MapEntry(key: reason, value: pages) in cases.entries) {
        final u = updater(pages);
        await expectLater(
          u.apply(),
          throwsA(isA<UpdateFailed>().having((e) => '$e', 'message', contains(reason))),
          reason: reason,
        );
        await u.relaunch(); // nothing downloaded: it just starts this app again
      }
      expect(spawned, everyElement([p.join(install, 'notelore.exe')]));
    });

    test('cleanup removes the .old files an earlier zip update left', () {
      write(p.join(install, 'notelore.exe.old'), 'older');
      write(p.join(install, 'data', 'app.so.old'), 'older');
      updater(good()).cleanup();
      expect(File(p.join(install, 'notelore.exe.old')).existsSync(), isFalse);
      expect(File(p.join(install, 'data', 'app.so.old')).existsSync(), isFalse);
      expect(read(p.join(install, 'notelore.exe')), 'old exe');
    });

    test('cleanup removes the setups that earlier updates left in temp', () async {
      final u = updater(good());
      await u.apply();
      await u.relaunch();
      final setupFolder = p.dirname(spawned.single.first);
      expect(Directory(setupFolder).existsSync(), isTrue);
      updater(good()).cleanup(); // the next start
      expect(Directory(setupFolder).existsSync(), isFalse);
    });

    test('cleanup of a folder that is gone does nothing', () {
      Updater(
        system: 'windows',
        executable: p.join(dir, 'gone', 'notelore.exe'),
        current: '0.2.0',
        temp: Directory(p.join(dir, 'temp'))..createSync(recursive: true),
        publicKey: base64Decode(testPublicKey),
        fetch: Pages({}).call,
        run: (command, args) async => ProcessResult(0, 0, '', ''),
        spawn: (_, _) async {},
      ).cleanup();
    });
  });

  group('macOS: the bundle from the dmg, swapped whole', () {
    late String bundle;
    late List<List<String>> spawned;
    late List<List<String>> ran;
    setUp(() {
      bundle = p.join(dir, 'Applications', 'notelore.app');
      write(p.join(bundle, 'Contents', 'MacOS', 'notelore'), 'old binary');
      spawned = [];
      ran = [];
    });

    /// hdiutil and ditto: attaching "mounts" a notelore.app, ditto copies it.
    Future<ProcessResult> tools(String command, List<String> args) async {
      ran.add([command, args.first]);
      if (command == 'hdiutil' && args.first == 'attach') {
        final mount = args[args.indexOf('-mountpoint') + 1];
        write(p.join(mount, 'notelore.app', 'Contents', 'MacOS', 'notelore'), 'new binary');
      } else if (command == 'ditto' && Directory(args[0]).existsSync()) {
        write(p.join(args[1], 'Contents', 'MacOS', 'notelore'), 'new binary');
      }
      return ProcessResult(0, 0, '', '');
    }

    Updater updater(Map<String, List<int>> pages, {Run? run}) => Updater(
      system: 'macos',
      executable: p.join(bundle, 'Contents', 'MacOS', 'notelore'),
      current: '0.2.0',
      temp: Directory(p.join(dir, 'temp'))..createSync(recursive: true),
      publicKey: base64Decode(testPublicKey),
      fetch: Pages(pages).call,
      run: run ?? tools,
      spawn: (exe, args) async => spawned.add([exe, ...args]),
    );

    final dmg = utf8.encode('dmg bytes');
    Map<String, List<int>> good() => {
      latestReleaseUrl: release(v),
      ...download('notelore-app-$v-macos.dmg', dmg),
    };

    test('the new bundle replaces the old one, which waits as .old', () async {
      write(p.join('$bundle.old', 'stale'), 'from an earlier update');
      final u = updater(good());
      expect(await u.apply(), v);
      expect(ran, [
        ['hdiutil', 'attach'],
        ['ditto', p.join(dir, 'Applications', '.notelore-update', 'mnt', 'notelore.app')],
        ['hdiutil', 'detach'],
      ]);
      expect(read(p.join(bundle, 'Contents', 'MacOS', 'notelore')), 'new binary');
      expect(read(p.join('$bundle.old', 'Contents', 'MacOS', 'notelore')), 'old binary');
      expect(Directory(p.join(dir, 'Applications', '.notelore-update')).existsSync(), isFalse);
      await u.relaunch();
      expect(spawned, [
        [p.join(bundle, 'Contents', 'MacOS', 'notelore')],
      ]);
      u.cleanup();
      expect(Directory('$bundle.old').existsSync(), isFalse);
      u.cleanup(); // nothing left: fine
    });

    test('a bundle swap that fails halfway puts the old app back', () async {
      final u = Updater(
        system: 'macos',
        executable: p.join(bundle, 'Contents', 'MacOS', 'notelore'),
        current: '0.2.0',
        temp: Directory(p.join(dir, 'temp'))..createSync(recursive: true),
        publicKey: base64Decode(testPublicKey),
        fetch: Pages(good()).call,
        run: tools,
        spawn: (_, _) async {},
        renameDirectory: (from, to) {
          // Only moving the new bundle in fails; putting the old one back works.
          if (to == bundle && from.contains('.notelore-update')) {
            throw const FileSystemException('Operation not permitted');
          }
          Directory(from).renameSync(to);
        },
      );
      await expectLater(u.apply(), throwsA(isA<FileSystemException>()));
      expect(read(p.join(bundle, 'Contents', 'MacOS', 'notelore')), 'old binary');
      expect(Directory('$bundle.old').existsSync(), isFalse);
    });

    test('a dmg that will not mount, or has no app, installs nothing', () async {
      Future<ProcessResult> broken(String command, List<String> args) async =>
          ProcessResult(0, 1, '', 'hdiutil: attach failed - image not recognized');
      await expectLater(
        updater(good(), run: broken).apply(),
        throwsA(
          isA<UpdateFailed>().having((e) => '$e', 'message', contains('image not recognized')),
        ),
      );
      Future<ProcessResult> empty(String command, List<String> args) async {
        ran.add([command, args.first]);
        return ProcessResult(0, 0, '', '');
      }

      await expectLater(
        updater(good(), run: empty).apply(),
        throwsA(isA<UpdateFailed>().having((e) => '$e', 'message', contains('notelore.app'))),
      );
      expect(ran.last, ['hdiutil', 'detach']); // the image is never left mounted
      expect(read(p.join(bundle, 'Contents', 'MacOS', 'notelore')), 'old binary');
    });

    test('a copy out of the dmg that fails installs nothing', () async {
      Future<ProcessResult> halfCopy(String command, List<String> args) async {
        await tools(command, args); // mounts, and ditto writes part of the bundle...
        return command == 'ditto'
            ? ProcessResult(0, 1, '', 'ditto: No space left on device') // ...then fails
            : ProcessResult(0, 0, '', '');
      }

      await expectLater(
        updater(good(), run: halfCopy).apply(),
        throwsA(isA<UpdateFailed>().having((e) => '$e', 'message', contains('No space left'))),
      );
      expect(read(p.join(bundle, 'Contents', 'MacOS', 'notelore')), 'old binary');
      expect(ran.last, ['hdiutil', 'detach']);
    });

    test('a folder next to the app that cannot be written says where to move it', () async {
      write(p.join(dir, 'Applications', '.notelore-update'), 'a file in the way');
      await expectLater(
        updater(good()).apply(),
        throwsA(isA<UpdateFailed>().having((e) => '$e', 'message', contains('a folder you own'))),
      );
    });
  });

  test('release builds on Windows, macOS and Android update themselves', () {
    Updater? make(String system, {String version = '1.0.0', String store = ''}) => updaterFor(
      system: system,
      version: version,
      executable: 'x',
      store: store,
      publicKey: testPublicKey,
    );
    expect(make('windows', version: ''), isNull);
    expect(make('linux'), isNull);
    final updater = make('macos')!;
    expect(updater.current, '1.0.0');
    expect(updater.publicKey, base64Decode(testPublicKey));
    expect(make('android')!.system, 'android');
    // Google Play updates the Play build itself: no updater there (#307).
    expect(make('android', store: 'play'), isNull);
    expect(make('windows', store: 'play'), isNotNull);
  });

  test('no updater without a release key to check downloads against (#312)', () {
    for (final key in ['', 'not base64!', base64Encode(List.filled(16, 1))]) {
      expect(
        updaterFor(system: 'windows', version: '1.0.0', executable: 'x', publicKey: key),
        isNull,
        reason: key,
      );
    }
  });

  test('a signature made by the release workflow (OpenSSL) verifies (#312)', () async {
    // `openssl pkeyutl -sign -rawin` with a throwaway key; only its public half is here.
    final message = utf8.encode('notelore-app-9.9.9-windows-x64-setup.exe from openssl');
    final key = base64Decode('a+DKKGLnlK7rMkZwviyq0TQ6upXl97ucx5zLPIKsiWI=');
    final signature = base64Decode(
      'aTJmNNFuV22+TxNu2faoV12rl5Z+uQ2IqT+wUpc8oNnJHL0Z207tWTHVVHYpVbArkFBjqyTKArukv9U5RVGMAA==',
    );
    expect(await signedBy(message, signature, key), isTrue);
    expect(await signedBy([...message, 0], signature, key), isFalse);
    expect(await signedBy(message, signature.sublist(1), key), isFalse);
  });

  group('Android: the APK, handed to the system installer', () {
    late List<String> opened;
    var allowed = true;
    setUp(() {
      opened = [];
      allowed = true;
    });

    Updater updater(Map<String, List<int>> pages) => Updater(
      system: 'android',
      executable: '/system/bin/app_process',
      current: '0.2.0',
      temp: Directory(p.join(dir, 'temp'))..createSync(recursive: true),
      publicKey: base64Decode(testPublicKey),
      fetch: Pages(pages).call,
      run: (command, args) async => fail('nothing runs on Android'),
      spawn: (_, _) async => fail('nothing is spawned on Android'),
      openInstaller: (apk) async {
        opened.add(apk);
        return allowed;
      },
    );

    final apk = utf8.encode('apk bytes');
    Map<String, List<int>> good() => {
      latestReleaseUrl: release(v),
      ...download('notelore-app-$v-android.apk', apk),
    };

    test('download and verify the APK, then open the installer', () async {
      final u = updater(good());
      expect(await u.apply(), v);
      await u.relaunch();
      expect(File(opened.single).readAsBytesSync(), apk);
      expect(p.basename(opened.single), 'notelore-app-$v-android.apk');
      // The next start removes it.
      u.cleanup();
      expect(File(opened.single).existsSync(), isFalse);
    });

    test('installs from Notelore not allowed yet: says so', () async {
      allowed = false;
      final u = updater(good());
      await u.apply();
      await expectLater(u.relaunch(), throwsA(isA<InstallNotAllowed>()));
    });

    test('a bad checksum installs nothing', () async {
      final u = updater({
        latestReleaseUrl: release(v),
        ...download('notelore-app-$v-android.apk', apk, digest: 'f' * 64),
      });
      await expectLater(u.apply(), throwsA(isA<UpdateFailed>()));
      expect(opened, isEmpty);
    });
  });
}

void transportTests() {
  test('httpFetch: the body, or UpdateFailed for an error status or no network', () async {
    final ok = MockClient((_) async => http.Response('body', 200));
    expect(utf8.decode(await httpFetch('https://x', client: ok)), 'body');
    final missing = MockClient((_) async => http.Response('', 404));
    await expectLater(
      httpFetch('https://x', client: missing),
      throwsA(isA<UpdateFailed>().having((e) => '$e', 'message', contains('HTTP 404'))),
    );
    final offline = MockClient((_) async => throw http.ClientException('no route'));
    await expectLater(httpFetch('https://x', client: offline), throwsA(isA<UpdateFailed>()));
  });

  test('httpFetch uses a real client by default (a loopback server here)', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen(
      (request) => request.response
        ..write('hello')
        ..close(),
    );
    expect(utf8.decode(await httpFetch('http://127.0.0.1:${server.port}/')), 'hello');
  });

  test('startDetached starts a program and does not wait for it', () async {
    await startDetached('git', ['--version']);
  });
}
