import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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
    expect(find.byType(MaterialBanner), findsNothing);
  });

  testWidgets('no banner when this is the newest version', (tester) async {
    await pump(tester, updater({latestReleaseUrl: release('0.2.0')}));
    expect(find.byType(MaterialBanner), findsNothing);
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
}
