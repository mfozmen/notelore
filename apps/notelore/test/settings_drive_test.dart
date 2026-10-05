import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore_core/notelore_core.dart';

import 'app_test.dart' show connect, phone, pumpApp;
import 'support.dart';

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a build without sign-in says so', (tester) async {
    phone(tester);
    await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    await openSettings(tester);
    expect(find.text('Sync is not set up in this build.'), findsOneWidget);
  });

  testWidgets('connect, sync now, disconnect', (tester) async {
    phone(tester);
    final harness = Harness(auth: FakeAuth());
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await openSettings(tester);
    expect(find.text('Back up and sync your notes across your devices.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Synced; nothing changed.'), findsOneWidget);
    harness.remote.texts['topics/t.md'] = '---\ntitle: T\n---\n# T\n';
    await tester.tap(find.byTooltip('Sync now'));
    await tester.pumpAndSettle();
    expect(find.text('Synced: 1 received.'), findsOneWidget);
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('T'), findsOneWidget); // the pulled note is listed
    await openSettings(tester);
    await tester.tap(find.byTooltip('Disconnect Google Drive'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
  });

  testWidgets('a refused sign-in shows why', (tester) async {
    phone(tester);
    final harness = Harness(auth: FakeAuth()..failSignIn = const SignInFailed('access_denied'));
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await openSettings(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Google sign-in failed: access_denied'), findsOneWidget);
  });

  testWidgets('while syncing the button waits', (tester) async {
    phone(tester);
    final harness = Harness(auth: FakeAuth()..granted = true);
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await openSettings(tester);
    session.syncing = true;
    session.notifyListeners();
    await tester.pump();
    expect(find.text('Syncing...'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.sync)).onPressed,
      isNull,
    );
    session.syncing = false;
    session.notifyListeners();
    await tester.pump();
  });
}
