import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notelore/src/update.dart';
import 'package:path/path.dart' as p;

const v = '9.9.9';

/// A GitHub "latest release" answer with the app assets for [version].
List<int> release(String version, {bool checksums = true}) {
  final apps = ['notelore-app-$version-windows-x64-setup.exe', 'notelore-app-$version-macos.dmg'];
  final names = [...apps, if (checksums) ...apps.map((a) => '$a.sha256')];
  return utf8.encode(
    jsonEncode({
      'tag_name': 'v$version',
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
    expect(() => assetName('1.2.3', 'linux'), throwsA(isA<UpdateFailed>()));
  });

  group('the daily check', () {
    late File cache;
    final now = DateTime.utc(2026, 10, 5, 12);
    setUp(() => cache = File(p.join(dir, 'state', 'update-check.json')));

    test('asks GitHub at most once a day', () async {
      final pages = Pages({latestReleaseUrl: release(v)});
      expect(await checkForUpdate(cache: cache, now: now, current: '0.2.0', fetch: pages.call), v);
      final later = now.add(const Duration(hours: 23));
      expect(
        await checkForUpdate(cache: cache, now: later, current: '0.2.0', fetch: pages.call),
        v,
      );
      expect(pages.calls, 1);
      expect(await checkForUpdate(cache: cache, now: later, current: v, fetch: pages.call), isNull);
      final tomorrow = now.add(const Duration(hours: 25));
      await checkForUpdate(cache: cache, now: tomorrow, current: '0.2.0', fetch: pages.call);
      expect(pages.calls, 2);
    });

    test('offline, garbled answers and a damaged cache are silent', () async {
      expect(
        await checkForUpdate(cache: cache, now: now, current: '0.2.0', fetch: Pages({}).call),
        isNull,
      );
      final garbled = Pages({latestReleaseUrl: utf8.encode('<html>')});
      expect(
        await checkForUpdate(cache: cache, now: now, current: '0.2.0', fetch: garbled.call),
        isNull,
      );
      write(cache.path, '{not json');
      final pages = Pages({latestReleaseUrl: release(v)});
      expect(await checkForUpdate(cache: cache, now: now, current: '0.2.0', fetch: pages.call), v);
    });

    test('a cache that cannot be written only means checking again', () async {
      Directory(cache.path).createSync(recursive: true); // a folder where the file should go
      final pages = Pages({latestReleaseUrl: release(v)});
      expect(await checkForUpdate(cache: cache, now: now, current: '0.2.0', fetch: pages.call), v);
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

    test('cleanup of a folder that is gone does nothing', () {
      Updater(
        system: 'windows',
        executable: p.join(dir, 'gone', 'notelore.exe'),
        current: '0.2.0',
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

    test('a folder next to the app that cannot be written says where to move it', () async {
      write(p.join(dir, 'Applications', '.notelore-update'), 'a file in the way');
      await expectLater(
        updater(good()).apply(),
        throwsA(isA<UpdateFailed>().having((e) => '$e', 'message', contains('a folder you own'))),
      );
    });
  });

  test('only release builds on Windows and macOS update themselves', () {
    expect(updaterFor(system: 'windows', version: '', executable: 'x'), isNull);
    expect(updaterFor(system: 'android', version: '1.0.0', executable: 'x'), isNull);
    final updater = updaterFor(system: 'macos', version: '1.0.0', executable: 'x')!;
    expect(updater.current, '1.0.0');
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
