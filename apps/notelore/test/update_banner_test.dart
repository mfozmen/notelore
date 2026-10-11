import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/app.dart';
import 'package:notelore/src/update.dart';
import 'package:path/path.dart' as p;

import 'app_test.dart' show connect, phone;
import 'support.dart';
import 'update_test.dart' show Pages, download, release;

const v = '9.9.9';

void main() {
  late String install;
  late List<String> spawned;
  late List<int> exits;
  setUp(() {
    final dir = Directory.systemTemp.createTempSync('notelore_banner_');
    addTearDown(() => dir.deleteSync(recursive: true));
    install = p.join(dir.path, 'Notelore');
    File(p.join(install, 'notelore.exe'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('old');
    spawned = [];
    exits = [];
  });

  Updater updater(Map<String, List<int>> pages) => Updater(
    system: 'windows',
    executable: p.join(install, 'notelore.exe'),
    current: '0.2.0',
    fetch: Pages(pages).call,
    run: (command, args) async => ProcessResult(0, 0, '', ''),
    spawn: (exe, args) async => spawned.add(exe),
  );

  Future<void> pump(WidgetTester tester, Updater updater) async {
    phone(tester);
    final session = Harness().session(owned: false);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await tester.pumpWidget(
      NoteloreApp(open: () async => session, updater: updater, exitApp: exits.add),
    );
    await tester.pumpAndSettle();
    await connect(tester, key: 'k');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }

  final setup = utf8.encode('setup');

  testWidgets('a newer release: update, restart', (tester) async {
    await pump(
      tester,
      updater({
        latestReleaseUrl: release(v),
        ...download('notelore-app-$v-windows-x64-setup.exe', setup),
      }),
    );
    expect(find.text('Notelore $v is available.'), findsOneWidget);
    await tester.tap(find.text('Update and restart'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(spawned.single, endsWith('notelore-app-$v-windows-x64-setup.exe')); // the setup
    expect(exits, [0]); // so the setup can replace the files
  });

  testWidgets('a setup that cannot start says why and the app keeps running', (tester) async {
    final u = Updater(
      system: 'windows',
      executable: p.join(install, 'notelore.exe'),
      current: '0.2.0',
      fetch: Pages({
        latestReleaseUrl: release(v),
        ...download('notelore-app-$v-windows-x64-setup.exe', setup),
      }).call,
      run: (command, args) async => ProcessResult(0, 0, '', ''),
      spawn: (exe, args) async => throw const ProcessException('setup.exe', [], 'blocked'),
    );
    await pump(tester, u);
    await tester.tap(find.text('Update and restart'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.textContaining('The setup could not start'), findsOneWidget);
    expect(find.text('Update and restart'), findsOneWidget); // try again
    expect(exits, isEmpty);
  });

  testWidgets('macOS: installed but not restarted says so, no second install', (tester) async {
    final bundle = p.join(p.dirname(install), 'Applications', 'notelore.app');
    File(p.join(bundle, 'Contents', 'MacOS', 'notelore'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('old');
    final u = Updater(
      system: 'macos',
      executable: p.join(bundle, 'Contents', 'MacOS', 'notelore'),
      current: '0.2.0',
      fetch: Pages({latestReleaseUrl: release(v), ...download('notelore-app-$v-macos.dmg', setup)})
          .call,
      run: (command, args) async {
        if (command == 'hdiutil' && args.first == 'attach') {
          File(p.join(args[args.indexOf('-mountpoint') + 1], 'notelore.app', 'x'))
            ..parent.createSync(recursive: true)
            ..writeAsStringSync('new');
        } else if (command == 'ditto') {
          File(p.join(args[1], 'x'))
            ..parent.createSync(recursive: true)
            ..writeAsStringSync('new');
        }
        return ProcessResult(0, 0, '', '');
      },
      spawn: (exe, args) async => throw const ProcessException('notelore', [], 'denied'),
    );
    await pump(tester, u);
    await tester.tap(find.text('Update and restart'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(
      find.text('Notelore $v is installed. Close and reopen Notelore to use it.'),
      findsOneWidget,
    );
    expect(find.text('Update and restart'), findsNothing);
    expect(exits, isEmpty);
  });

  testWidgets('a failed update says why and the app keeps running', (tester) async {
    await pump(tester, updater({latestReleaseUrl: release(v, checksums: false)}));
    await tester.tap(find.text('Update and restart'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.textContaining('publishes no checksum'), findsOneWidget);
    expect(exits, isEmpty);
  });

  testWidgets('later hides the banner; nothing newer shows none', (tester) async {
    await pump(tester, updater({latestReleaseUrl: release(v)}));
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('Later'), findsNothing);
  });

  testWidgets('no banner when this is the newest version', (tester) async {
    await pump(tester, updater({latestReleaseUrl: release('0.2.0')}));
    expect(find.text('Later'), findsNothing);
  });

  testWidgets('while installing the buttons wait', (tester) async {
    final slow = Updater(
      system: 'windows',
      executable: p.join(install, 'notelore.exe'),
      current: '0.2.0',
      fetch: (url) async {
        if (url != latestReleaseUrl) await Completer<void>().future; // never arrives
        return release(v);
      },
      run: (command, args) async => ProcessResult(0, 0, '', ''),
      spawn: (exe, args) async {},
    );
    await pump(tester, slow);
    await tester.tap(find.text('Update and restart'));
    await tester.pump();
    expect(find.text('Installing Notelore $v...'), findsOneWidget);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Later')).onPressed, isNull);
  });

  testWidgets('Settings checks by hand: up to date, offline, then a new release', (tester) async {
    final pages = Pages({latestReleaseUrl: release('0.2.0')});
    await pump(
      tester,
      Updater(
        system: 'windows',
        executable: p.join(install, 'notelore.exe'),
        current: '0.2.0',
        fetch: pages.call,
        run: (command, args) async => ProcessResult(0, 0, '', ''),
        spawn: (exe, args) async => spawned.add(exe),
      ),
    );
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    Future<void> check() async {
      await tester.tap(find.text('Check for updates'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }

    await check();
    expect(find.text('Notelore is up to date.'), findsOneWidget);
    pages.pages.remove(latestReleaseUrl);
    await check();
    expect(find.textContaining('Could not check for updates'), findsOneWidget);
    pages.pages[latestReleaseUrl] = release(v);
    await check();
    expect(find.text('Notelore $v is available.'), findsWidgets); // the banner too
    expect(find.text('Update and restart'), findsOneWidget);
  });

  /// Six hours pass while the app is open.
  Future<void> tick(WidgetTester tester) async {
    await tester.pump(const Duration(hours: 6));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }

  testWidgets('while open it checks again every 6 hours', (tester) async {
    final pages = Pages({latestReleaseUrl: release('0.2.0')});
    await pump(
      tester,
      Updater(
        system: 'windows',
        executable: p.join(install, 'notelore.exe'),
        current: '0.2.0',
        fetch: pages.call,
        run: (command, args) async => ProcessResult(0, 0, '', ''),
        spawn: (exe, args) async => spawned.add(exe),
      ),
    );
    expect(find.text('Update and restart'), findsNothing);
    pages.pages[latestReleaseUrl] = release(v);
    await tester.pump(const Duration(hours: 6));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Update and restart'), findsOneWidget);
    // Offline on a later tick: quiet, the banner stays.
    pages.pages.remove(latestReleaseUrl);
    await tick(tester);
    expect(find.text('Update and restart'), findsOneWidget);
    // "Later" sticks: the next tick does not bring the same version back.
    pages.pages[latestReleaseUrl] = release(v);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    await tick(tester);
    expect(find.text('Update and restart'), findsNothing);
    // A newer one than the dismissed version does show.
    pages.pages[latestReleaseUrl] = release('10.0.0');
    await tick(tester);
    expect(find.text('Notelore 10.0.0 is available.'), findsOneWidget);
  });

  testWidgets('a tick leaves the banner alone while an update installs', (tester) async {
    final pages = Pages({
      latestReleaseUrl: release(v),
      ...download('notelore-app-$v-windows-x64-setup.exe', utf8.encode('setup')),
    });
    final hold = Completer<void>();
    await pump(
      tester,
      Updater(
        system: 'windows',
        executable: p.join(install, 'notelore.exe'),
        current: '0.2.0',
        fetch: (url) async {
          if (url.endsWith('setup.exe')) await hold.future; // the download is slow
          return pages.call(url);
        },
        run: (command, args) async => ProcessResult(0, 0, '', ''),
        spawn: (exe, args) async => spawned.add(exe),
      ),
    );
    await tester.tap(find.text('Update and restart'));
    await tester.pump();
    pages.pages[latestReleaseUrl] = release('0.2.0'); // a tick would clear the banner
    await tick(tester);
    expect(find.textContaining('Installing Notelore $v'), findsOneWidget);
    hold.complete();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
  });

  testWidgets('Android: Update opens the installer and the app keeps running', (tester) async {
    final opened = <String>[];
    var allowed = false;
    var failInstaller = false;
    await pump(
      tester,
      Updater(
        system: 'android',
        executable: '/system/bin/app_process',
        current: '0.2.0',
        fetch: Pages({
          latestReleaseUrl: release(v),
          ...download('notelore-app-$v-android.apk', utf8.encode('apk')),
        }).call,
        run: (command, args) async => ProcessResult(0, 0, '', ''),
        spawn: (exe, args) async => spawned.add(exe),
        openInstaller: (apk) async {
          if (failInstaller) throw PlatformException(code: 'install_failed', message: 'no space');
          opened.add(apk);
          return allowed;
        },
      ),
    );
    // Not allowed yet: the setting opened, the banner says what to do.
    await tester.tap(find.text('Update'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Allow Notelore to install apps'), findsOneWidget);
    allowed = true;
    await tester.tap(find.text('Update'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(opened, hasLength(2));
    expect(exits, isEmpty); // the installer takes over; the app is not closed
    expect(spawned, isEmpty);
    // The installer could not open (no space, no app for it): the banner says so.
    allowed = true;
    failInstaller = true;
    await tester.tap(find.text('Update'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.textContaining('The setup could not start'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget); // still offered, nothing was installed
  });

  testWidgets('androidInstaller asks MainActivity, false unless it says true', (tester) async {
    final asked = <Object?>[];
    Object? answer = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('io.github.mfozmen.notelore/install'),
      (call) async {
        asked.add([call.method, call.arguments]);
        return answer;
      },
    );
    expect(await androidInstaller('/cache/a.apk'), isTrue);
    answer = null;
    expect(await androidInstaller('/cache/a.apk'), isFalse);
    expect(asked.first, ['install', '/cache/a.apk']);
  });
}
