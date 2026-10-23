import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' show Ed25519, SimpleKeyPair;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notelore/src/update.dart';
import 'package:path/path.dart' as p;

const v = '9.9.9';

/// A GitHub "latest release" answer with the app assets for [version].
List<int> release(
  String version, {
  bool checksums = true,
  bool signatures = false,
  List<String> systems = const ['windows', 'macos', 'android'],
  String abi = '',
}) {
  final apps = [
    for (final system in systems) assetName(version, system),
    if (systems.contains('android') && abi.isNotEmpty)
      assetName(version, 'android', abi: abi),
  ];
  final names = [
    ...apps,
    if (checksums) ...apps.map((a) => '$a.sha256'),
    if (signatures) ...apps.map((a) => '$a.sha256.sig'),
  ];
  return utf8.encode(
    jsonEncode({
      'tag_name': 'v$version',
      'html_url': 'https://github.com/mfozmen/notelore/releases/tag/v$version',
      'body':
          '## v$version\n\n### Bug Fixes\n\n- The chat scrolls ([`abc`](https://x))\n\n'
          '### Features\n\n- Notes sync faster ([#1](https://x), [`def`](https://x))\n\n'
          '- Voice works offline ([`123`](https://x))\n\n- A third one\n',
      'assets': [
        for (final n in names) {'name': n, 'browser_download_url': 'https://dl/$n'},
      ],
    }),
  );
}

/// Fetches from a map of URL -> bytes; anything else is "offline".
class Pages {
  Pages(this.pages);

  final Map<String, List<int>> pages;
  var calls = 0;

  Future<List<int>> call(String url) async {
    calls++;
    final page = pages[url];
    if (page == null) throw UpdateFailed('offline: $url');
    return page;
  }
}

/// The zip download and its sha256sum line.
Map<String, List<int>> download(String name, List<int> zip, {String? digest}) => {
  'https://dl/$name': zip,
  'https://dl/$name.sha256': utf8.encode('${digest ?? sha256.convert(zip)}  $name\n'),
};

/// The signing key of the release workflow, and its public half as the app
/// pins it (base64).
Future<({SimpleKeyPair pair, String key})> releaseKey() async {
  final pair = await Ed25519().newKeyPair();
  return (pair: pair, key: base64.encode((await pair.extractPublicKey()).bytes));
}

/// [download] plus the `.sig` of its checksum, signed with [pair] as release.yml
/// signs it: the base64 Ed25519 signature of the `.sha256` file's bytes.
Future<Map<String, List<int>>> signedDownload(
  String name,
  List<int> data,
  SimpleKeyPair pair,
) async {
  final pages = download(name, data);
  final signature = await Ed25519().sign(pages['https://dl/$name.sha256']!, keyPair: pair);
  return {
    ...pages,
    'https://dl/$name.sha256.sig': utf8.encode('${base64.encode(signature.bytes)}\n'),
  };
}

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
    expect(
      assetName('1.2.3', 'android', abi: 'arm64-v8a'),
      'notelore-app-1.2.3-android-arm64-v8a.apk',
    );
    expect(() => assetName('1.2.3', 'linux'), throwsA(isA<UpdateFailed>()));
  });

  test('names the Android ABI, and leaves a CPU it does not build for empty', () {
    expect(abiName(Abi.androidArm64), 'arm64-v8a');
    expect(abiName(Abi.androidArm), 'armeabi-v7a');
    expect(abiName(Abi.androidX64), 'x86_64');
    expect(abiName(Abi.windowsX64), '');
  });

  test('a release says what it brings: features first, then fixes, two at most (#288)', () {
    expect(
      releaseHighlights(
        '### Bug Fixes\n\n- Fix one ([`a`](u))\n\n### Features\n\n- New one ([#1](u), [`b`](u))\n',
      ),
      ['New one', 'Fix one'],
    );
    expect(releaseHighlights('### Chores\n\n- tidy\n'), isEmpty);
    expect(releaseHighlights(null), isEmpty);
  });

  group('the check', () {
    test('Android takes the APK for its ABI, or the universal one', () async {
      final arm = Pages({latestReleaseUrl: release(v, abi: 'arm64-v8a')});
      expect(
        await checkForUpdate(
          current: '0.2.0',
          fetch: arm.call,
          system: 'android',
          abi: 'arm64-v8a',
        ),
        v,
      );
      final universal = Pages({latestReleaseUrl: release(v)});
      expect(
        await checkForUpdate(
          current: '0.2.0',
          fetch: universal.call,
          system: 'android',
          abi: 'x86_64',
        ),
        v,
      );
    });

    test('a newer release comes with its highlights and its page (#288)', () async {
      final pages = Pages({latestReleaseUrl: release(v)});
      final found = await checkRelease(current: '0.2.0', fetch: pages.call, system: 'windows');
      expect(found!.version, v);
      expect(found.highlights, ['Notes sync faster', 'Voice works offline']);
      expect(found.page, 'https://github.com/mfozmen/notelore/releases/tag/v$v');
      expect(await checkRelease(current: v, fetch: pages.call, system: 'windows'), isNull);
    });

    test('asks GitHub every time, so each start hears of a new release', () async {
      final pages = Pages({latestReleaseUrl: release('0.2.0')});
      expect(await checkForUpdate(current: '0.2.0', fetch: pages.call, system: 'windows'), isNull);
      pages.pages[latestReleaseUrl] = release(v); // published a minute later
      expect(await checkForUpdate(current: '0.2.0', fetch: pages.call, system: 'windows'), v);
      expect(await checkForUpdate(current: v, fetch: pages.call, system: 'windows'), isNull);
      expect(pages.calls, 3);
    });

    test(
      'a release whose file for this system, or its checksum, is not up yet waits (#476)',
      () async {
        // The app said v0.17.0 was there while its files were still building.
        final building = Pages({
          latestReleaseUrl: release(v, systems: ['windows']),
        });
        expect(
          await checkRelease(current: '0.2.0', fetch: building.call, system: 'android'),
          isNull,
        );
        expect(
          (await checkRelease(current: '0.2.0', fetch: building.call, system: 'windows'))!.version,
          v,
        );
        final unsummed = Pages({latestReleaseUrl: release(v, checksums: false)});
        expect(await checkRelease(current: '0.2.0', fetch: unsummed.call, system: 'macos'), isNull);
        // Assets GitHub never sends in this shape: still silent, never a crash at start.
        for (final assets in <Object?>[
          null,
          <String, Object?>{},
          ['not a map'],
        ]) {
          final odd = Pages({
            latestReleaseUrl: utf8.encode(jsonEncode({'tag_name': 'v$v', 'assets': assets})),
          });
          expect(await checkRelease(current: '0.2.0', fetch: odd.call, system: 'macos'), isNull);
        }
      },
    );

    test('an app that pins a key waits for a release that signed its file (#485)', () async {
      final unsigned = Pages({latestReleaseUrl: release(v)});
      expect(
        await checkRelease(current: '0.2.0', fetch: unsigned.call, system: 'macos', signed: true),
        isNull,
      );
      final signed = Pages({latestReleaseUrl: release(v, signatures: true)});
      expect(
        (await checkRelease(
          current: '0.2.0',
          fetch: signed.call,
          system: 'macos',
          signed: true,
        ))!.version,
        v,
      );
    });

    test('offline or a garbled answer is silent, unless forced', () async {
      expect(
        await checkForUpdate(current: '0.2.0', fetch: Pages({}).call, system: 'windows'),
        isNull,
      );
      final garbled = Pages({latestReleaseUrl: utf8.encode('<html>')});
      expect(
        await checkForUpdate(current: '0.2.0', fetch: garbled.call, system: 'windows'),
        isNull,
      );
      await expectLater(
        checkForUpdate(current: '0.2.0', fetch: Pages({}).call, system: 'windows', force: true),
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
      fetch: Pages(pages).call,
      run: (command, args) async => fail('nothing is unpacked on Windows'),
      spawn: spawn ?? (exe, args) async => spawned.add([exe, ...args]),
    );

    final setup = utf8.encode('setup bytes');
    Map<String, List<int>> good() => {
      latestReleaseUrl: release(v),
      ...download('notelore-app-$v-windows-x64-setup.exe', setup),
    };

    test('download and verify the setup, then run it silently for this user (#493)', () async {
      final u = updater(good());
      expect(await u.apply(), v);
      expect(read(p.join(install, 'notelore.exe')), 'old exe'); // the setup replaces it
      await u.relaunch();
      final [exe, ...args] = spawned.single;
      expect(File(exe).readAsBytesSync(), setup);
      expect(p.basename(exe), 'notelore-app-$v-windows-x64-setup.exe');
      expect(args, ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART']);
    });

    test('apply reports checking, downloading bytes, verifying and installing', () async {
      final states = <UpdateProgress>[];
      final u = Updater(
        system: 'windows',
        executable: p.join(install, 'notelore.exe'),
        current: '0.2.0',
        temp: Directory(p.join(dir, 'progress-temp'))..createSync(recursive: true),
        fetch: Pages(good()).call,
        download: (url, {onProgress}) async {
          onProgress?.call(1, 2);
          onProgress?.call(2, 2);
          return setup;
        },
        run: (command, args) async => fail('nothing is unpacked on Windows'),
        spawn: (exe, args) async {},
      );
      expect(await u.apply(onProgress: states.add), v);
      expect(states.map((s) => s.phase), [
        UpdatePhase.checking,
        UpdatePhase.downloading,
        UpdatePhase.downloading,
        UpdatePhase.downloading,
        UpdatePhase.verifying,
        UpdatePhase.installing,
      ]);
      expect(states.where((s) => s.phase == UpdatePhase.downloading).last.received, 2);
      expect(states.where((s) => s.phase == UpdatePhase.downloading).last.total, 2);
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
        'has no app for this device': {
          latestReleaseUrl: utf8.encode(jsonEncode({'tag_name': 'v$v', 'assets': <Object>[]})),
        },
        'is empty': {...good(), 'https://dl/notelore-app-$v-windows-x64-setup.exe.sha256': <int>[]},
        'names no file': {
          ...good(),
          'https://dl/notelore-app-$v-windows-x64-setup.exe.sha256': utf8.encode('${'a' * 64}\n'),
        },
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

    group('with a pinned key (#485)', () {
      late SimpleKeyPair pair;
      late String key;
      setUp(() async => (:pair, :key) = await releaseKey());

      Updater pinned(Map<String, List<int>> pages, String key) => Updater(
        system: 'windows',
        executable: p.join(install, 'notelore.exe'),
        current: '0.2.0',
        temp: Directory(p.join(dir, 'temp'))..createSync(recursive: true),
        fetch: Pages(pages).call,
        run: (command, args) async => fail('nothing is unpacked on Windows'),
        spawn: (exe, args) async => spawned.add([exe, ...args]),
        publicKey: key,
      );

      const name = 'notelore-app-$v-windows-x64-setup.exe';

      test('a setup whose checksum the release key signed is installed', () async {
        final pages = {
          latestReleaseUrl: release(v, signatures: true),
          ...await signedDownload(name, setup, pair),
        };
        final u = pinned(pages, key);
        expect(await u.apply(), v);
        await u.relaunch();
        expect(File(spawned.single.first).readAsBytesSync(), setup);
      });

      test('no signature, another key\'s, a garbled one or a changed checksum: nothing', () async {
        final good = await signedDownload(name, setup, pair);
        final other = await releaseKey();
        final evil = utf8.encode('evil setup');
        // Whoever can write to the release replaces the setup and its checksum.
        final swapped = {...good, ...download(name, evil)};
        final cases = {
          'publishes no signature': {latestReleaseUrl: release(v), ...download(name, setup)},
          'another key': {
            latestReleaseUrl: release(v, signatures: true),
            ...await signedDownload(name, setup, other.pair),
          },
          'garbled': {
            latestReleaseUrl: release(v, signatures: true),
            ...good,
            'https://dl/$name.sha256.sig': utf8.encode('not base64!'),
          },
          'too short': {
            latestReleaseUrl: release(v, signatures: true),
            ...good,
            'https://dl/$name.sha256.sig': utf8.encode(base64.encode([1, 2, 3])),
          },
          'replaced': {latestReleaseUrl: release(v, signatures: true), ...swapped},
        };
        for (final MapEntry(key: reason, value: pages) in cases.entries) {
          final why = reason == 'publishes no signature' ? reason : 'not signed by Notelore';
          await expectLater(
            pinned(pages, key).apply(),
            throwsA(isA<UpdateFailed>().having((e) => '$e', 'message', contains(why))),
            reason: reason,
          );
        }
        // An older release's file with its own signed checksum, put up under a
        // newer version's name: the signature holds, the name does not.
        const old = 'notelore-app-1.0.0-windows-x64-setup.exe';
        final replayed = await signedDownload(old, setup, pair);
        await expectLater(
          pinned({
            latestReleaseUrl: release(v, signatures: true),
            'https://dl/$name': setup,
            'https://dl/$name.sha256': replayed['https://dl/$old.sha256']!,
            'https://dl/$name.sha256.sig': replayed['https://dl/$old.sha256.sig']!,
          }, key).apply(),
          throwsA(isA<UpdateFailed>().having((e) => '$e', 'message', contains('is for $old'))),
        );
        // A key the app was built with that is not one: nothing passes either.
        await expectLater(
          pinned({latestReleaseUrl: release(v, signatures: true), ...good}, 'AAAA').apply(),
          throwsA(isA<UpdateFailed>()),
        );
        expect(spawned, isEmpty);
      });
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

    /// The macOS the new bundle needs, written into its Info.plist when set.
    String? needs;
    setUp(() {
      needs = null;
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
        if (needs case final version?) {
          write(
            p.join(args[1], 'Contents', 'Info.plist'),
            '<dict>\n\t<key>LSMinimumSystemVersion</key>\n\t<string>$version</string>\n</dict>',
          );
        }
      }
      return ProcessResult(0, 0, '', '');
    }

    Updater updater(Map<String, List<int>> pages, {Run? run, String os = 'Version 15.1'}) =>
        Updater(
          system: 'macos',
          osVersion: os,
          executable: p.join(bundle, 'Contents', 'MacOS', 'notelore'),
          current: '0.2.0',
          temp: Directory(p.join(dir, 'temp'))..createSync(recursive: true),
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

    test(
      'a release that needs a newer macOS is not installed: this app keeps working (#328)',
      () async {
        needs = '14.0';
        await expectLater(
          updater(good(), os: 'Version 13.6.1 (Build 22G313)').apply(),
          throwsA(
            isA<UpdateFailed>().having((e) => e.message, 'message', contains('needs macOS 14.0')),
          ),
        );
        expect(read(p.join(bundle, 'Contents', 'MacOS', 'notelore')), 'old binary');
        expect(Directory(p.join(dir, 'Applications', '.notelore-update')).existsSync(), isFalse);
        // On a new enough Mac it goes in as before.
        expect(await updater(good(), os: 'Version 14.5 (Build 23F79)').apply(), v);
        expect(read(p.join(bundle, 'Contents', 'MacOS', 'notelore')), 'new binary');
      },
    );

    test('a bundle swap that fails halfway puts the old app back', () async {
      final u = Updater(
        system: 'macos',
        executable: p.join(bundle, 'Contents', 'MacOS', 'notelore'),
        current: '0.2.0',
        temp: Directory(p.join(dir, 'temp'))..createSync(recursive: true),
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
    expect(updaterFor(system: 'windows', version: '', executable: 'x', key: 'k'), isNull);
    expect(updaterFor(system: 'linux', version: '1.0.0', executable: 'x', key: 'k'), isNull);
    final updater = updaterFor(system: 'macos', version: '1.0.0', executable: 'x', key: 'k')!;
    expect(updater.current, '1.0.0');
    expect(updater.publicKey, 'k'); // the key the release build pins (#485)
    final android = updaterFor(
      system: 'android',
      version: '1.0.0',
      executable: 'x',
      key: 'k',
      abi: 'arm64-v8a',
    );
    expect(android!.system, 'android');
    expect(android.abi, 'arm64-v8a');
    // A release build without the key never falls back to checksums alone.
    expect(updaterFor(system: 'macos', version: '1.0.0', executable: 'x', key: ''), isNull);
    expect(updaterFor(system: 'macos', version: '1.0.0', executable: 'x'), isNull); // this build
  });

  group('Android: the APK, handed to the system installer', () {
    late List<String> opened;
    var allowed = true;
    setUp(() {
      opened = [];
      allowed = true;
    });

    Updater updater(Map<String, List<int>> pages, {String abi = ''}) => Updater(
      system: 'android',
      abi: abi,
      executable: '/system/bin/app_process',
      current: '0.2.0',
      temp: Directory(p.join(dir, 'temp'))..createSync(recursive: true),
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

    test('downloads the APK for this ABI, not the universal one', () async {
      final arm = utf8.encode('arm64 apk');
      final u = updater({
        latestReleaseUrl: release(v, abi: 'arm64-v8a'),
        ...download('notelore-app-$v-android.apk', apk),
        ...download('notelore-app-$v-android-arm64-v8a.apk', arm),
      }, abi: 'arm64-v8a');
      expect(await u.apply(), v);
      await u.relaunch();
      expect(File(opened.single).readAsBytesSync(), arm);
      expect(p.basename(opened.single), 'notelore-app-$v-android-arm64-v8a.apk');
    });

    test('falls back to the universal APK when this ABI is not published', () async {
      final u = updater(good(), abi: 'x86_64');
      expect(await u.apply(), v);
      await u.relaunch();
      expect(File(opened.single).readAsBytesSync(), apk);
      expect(p.basename(opened.single), 'notelore-app-$v-android.apk');
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

  test('httpDownload streams the body and its progress, or UpdateFailed', () async {
    final seen = <(int, int?)>[];
    final ok = MockClient((_) async => http.Response('body', 200));
    expect(
      utf8.decode(
        await httpDownload(
          'https://x',
          client: ok,
          onProgress: (received, total) => seen.add((received, total)),
        ),
      ),
      'body',
    );
    expect(seen, [(4, 4)]);
    final missing = MockClient((_) async => http.Response('', 404));
    await expectLater(
      httpDownload('https://x', client: missing),
      throwsA(isA<UpdateFailed>().having((e) => '$e', 'message', contains('HTTP 404'))),
    );
    final offline = MockClient((_) async => throw http.ClientException('no route'));
    await expectLater(httpDownload('https://x', client: offline), throwsA(isA<UpdateFailed>()));
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

  test('httpDownload uses a real client by default (a loopback server here)', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen(
      (request) => request.response
        ..write('hello')
        ..close(),
    );
    expect(utf8.decode(await httpDownload('http://127.0.0.1:${server.port}/')), 'hello');
  });

  test('startDetached starts a program and does not wait for it', () async {
    await startDetached('git', ['--version']);
  });
}
