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
    run: (command, args) async {
      File(p.join(args.last, 'notelore.exe')).writeAsStringSync('new');
      return ProcessResult(0, 0, '', '');
    },
    spawn: (exe) async => spawned.add(exe),
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

  final zip = utf8.encode('zip');

  testWidgets('a newer release: update, restart', (tester) async {
    await pump(
      tester,
      updater({latestReleaseUrl: release(v), ...download('notelore-app-$v-windows-x64.zip', zip)}),
    );
    expect(find.text('Notelore $v is available.'), findsOneWidget);
    await tester.tap(find.text('Update and restart'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(File(p.join(install, 'notelore.exe')).readAsStringSync(), 'new');
    expect(spawned, [p.join(install, 'notelore.exe')]);
    expect(exits, [0]);
  });

  testWidgets('installed but not restarted: says so and offers no second install', (tester) async {
    final u = Updater(
      system: 'windows',
      executable: p.join(install, 'notelore.exe'),
      current: '0.2.0',
      fetch: Pages({
        latestReleaseUrl: release(v),
        ...download('notelore-app-$v-windows-x64.zip', zip),
      }).call,
      run: (command, args) async {
        File(p.join(args.last, 'notelore.exe')).writeAsStringSync('new');
        return ProcessResult(0, 0, '', '');
      },
      spawn: (exe) async => throw const ProcessException('notelore.exe', [], 'access denied'),
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
      spawn: (exe) async {},
    );
    await pump(tester, slow);
    await tester.tap(find.text('Update and restart'));
    await tester.pump();
    expect(find.text('Installing Notelore $v...'), findsOneWidget);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Later')).onPressed, isNull);
  });
}
