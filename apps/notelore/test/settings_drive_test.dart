import 'dart:async';

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

  testWidgets('Google first (Drive with it), sync now; disconnecting signs out', (tester) async {
    phone(tester);
    final harness = Harness(auth: FakeAuth());
    await pumpApp(tester, harness);
    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();
    await connect(tester, key: 'k');
    await openSettings(tester);
    expect(find.text('Synced; nothing changed.'), findsOneWidget);
    harness.remote.texts['topics/t.md'] = '---\ntitle: T\n---\n# T\n';
    await tester.ensureVisible(find.byTooltip('Sync now'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sync now'));
    await tester.pumpAndSettle();
    expect(find.text('Synced: 1 received.'), findsOneWidget);
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('T'), findsOneWidget); // the pulled note is listed
    await openSettings(tester);
    await tester.ensureVisible(find.byTooltip('Disconnect Google Drive'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Disconnect Google Drive'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with Google'), findsOneWidget); // back to the first step
  });

  testWidgets('coming back to the app syncs', (tester) async {
    phone(tester);
    final harness = Harness(auth: FakeAuth()..granted = true);
    await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    harness.remote.texts['topics/t.md'] = '---\ntitle: T\n---\n# T\n';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('T'), findsOneWidget);
  });

  testWidgets('an expired grant keeps the app and its notes; Settings connects again (#208)', (
    tester,
  ) async {
    phone(tester);
    final auth = FakeAuth()..granted = true; // signed in on an earlier run
    final harness = Harness(auth: auth);
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    createNote(harness.paths.notes.path, 'topic', 'Mopsos', today: today);
    harness.remote.failure = const NotSignedIn('Google Drive access was revoked or expired');
    await session.syncNow();
    await tester.pumpAndSettle();
    expect(find.text('Sign in with Google'), findsNothing); // still in the app
    await openSettings(tester);
    expect(find.text('Google Drive access was revoked or expired; connect again.'), findsOneWidget);
    auth.failSignIn = const SignInFailed('access_denied');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Google sign-in failed: access_denied'), findsOneWidget);
    auth.failSignIn = null;
    harness.remote.failure = null;
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Synced: 1 sent.'), findsOneWidget); // the note made meanwhile goes up
  });

  testWidgets('while syncing the button waits', (tester) async {
    phone(tester);
    final harness = Harness(auth: FakeAuth()..granted = true);
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await openSettings(tester);
    harness.remote.hold = Completer<void>(); // the next sync stays in flight
    unawaited(session.syncNow());
    await tester.pump();
    expect(find.text('Syncing...'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.sync)).onPressed,
      isNull,
    );
    harness.remote.hold!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Syncing...'), findsNothing);
  });

  group('many notes gone from Drive at once (#454)', () {
    Future<Harness> wiped(WidgetTester tester) async {
      phone(tester);
      final harness = Harness(auth: FakeAuth()..granted = true);
      for (final name in ['A', 'B', 'C', 'D']) {
        createNote(harness.paths.notes.path, 'topic', name, today: today);
      }
      await pumpApp(tester, harness);
      await connect(tester, key: 'k');
      harness.remote.texts.removeWhere((rel, _) => rel.endsWith('.md'));
      await openSettings(tester);
      await tester.ensureVisible(find.byTooltip('Sync now'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sync now'));
      await tester.pumpAndSettle();
      expect(
        find.text('4 notes were removed from Google Drive at once. Notelore kept them here.'),
        findsOneWidget,
      );
      return harness;
    }

    testWidgets('a banner offers Restore to Drive', (tester) async {
      final harness = await wiped(tester);
      await tester.tap(find.text('Restore to Drive'));
      await tester.pumpAndSettle();
      expect(find.textContaining('removed from Google Drive'), findsNothing);
      expect(harness.remote.texts.keys.where((rel) => rel.endsWith('.md')), hasLength(4));
    });

    testWidgets('Delete here too asks first', (tester) async {
      await wiped(tester);
      await tester.tap(find.text('Delete here too'));
      await tester.pumpAndSettle();
      expect(find.text('Delete 4 notes here too?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.textContaining('removed from Google Drive'), findsOneWidget);
      await tester.tap(find.text('Delete here too'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.textContaining('removed from Google Drive'), findsNothing);
      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();
      expect(find.text('A'), findsNothing);
    });
  });
}
