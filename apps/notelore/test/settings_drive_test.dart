import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore_core/notelore_core.dart';

import 'app_test.dart' show connect, phone, pumpApp;
import 'support.dart';

Future<void> openSync(WidgetTester tester) => openSettings(tester, 'Sync');

void main() {
  testWidgets('a build without sign-in says so', (tester) async {
    phone(tester);
    await pumpApp(tester, Harness());
    await connect(tester, key: 'k');
    await openSync(tester);
    expect(find.text('Sync is not set up in this build.'), findsOneWidget);
  });

  testWidgets('Google first (Drive with it), sync now; disconnecting signs out', (tester) async {
    phone(tester);
    final harness = Harness(auth: FakeAuth());
    await pumpApp(tester, harness);
    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();
    await connect(tester, key: 'k');
    await openSync(tester);
    expect(find.text('Synced; nothing changed.'), findsOneWidget);
    harness.remote.texts['topics/t.md'] = '---\ntitle: T\n---\n# T\n';
    await tester.ensureVisible(find.byTooltip('Sync now'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Sync now'));
    await tester.pumpAndSettle();
    expect(find.text('Synced: 1 received.'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('T'), findsOneWidget); // the pulled note is listed
    await openSync(tester);
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
    await openSync(tester);
    expect(find.text('Signed out of Google. Connect again.'), findsOneWidget);
    auth.failSignIn = const SignInFailed('access_denied');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Sign-in did not finish. Please try again.'), findsOneWidget); // never raw
    // A box left unticked on Google's consent screen: says to tick them all (#484).
    auth.failSignIn = const PartialGrant();
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
    expect(find.textContaining('leave every box ticked'), findsOneWidget);
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
    await openSync(tester);
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

  group('Drive needs a sign-in again: a banner says so (#479)', () {
    const banner = 'Google Drive needs you to sign in again to keep syncing your notes.';

    /// A phone signed in before v0.17.0: its grant lacks the hidden folder's scope.
    Future<FakeAuth> upgraded(WidgetTester tester) async {
      phone(tester);
      final auth = FakeAuth()..granted = true;
      final harness = Harness(auth: auth);
      final before = harness.session();
      await before.load();
      await before.connectDrive();
      auth.granted = false;
      await pumpApp(tester, harness);
      await connect(tester, key: 'k');
      return auth;
    }

    testWidgets('Connect signs in, and syncing goes on', (tester) async {
      final auth = await upgraded(tester);
      expect(find.text(banner), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Connect'));
      await tester.pumpAndSettle();
      expect(auth.granted, isTrue);
      expect(find.text(banner), findsNothing);
    });

    testWidgets('a sign-in that fails says so; Later puts it off', (tester) async {
      final auth = await upgraded(tester);
      auth.failSignIn = const SignInFailed('access_denied');
      await tester.tap(find.widgetWithText(TextButton, 'Connect'));
      await tester.pumpAndSettle();
      expect(find.text('Sign-in did not finish. Please try again.'), findsOneWidget);
      auth.failSignIn = const PartialGrant();
      await tester.tap(find.widgetWithText(TextButton, 'Connect'));
      await tester.pumpAndSettle();
      expect(find.textContaining('leave every box ticked'), findsOneWidget);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text(banner), findsNothing);
    });
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
      await openSync(tester);
      await tester.ensureVisible(find.byTooltip('Sync now'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Sync now'));
      await tester.pumpAndSettle();
      await tester.pageBack(); // the banner is above the task screens
      await tester.pumpAndSettle();
      expect(
        find.text('4 notes were removed from Google Drive at once. Notelore kept them here.'),
        findsOneWidget,
      );
      return harness;
    }

    testWidgets('a banner offers Restore to Drive', (tester) async {
      final harness = await wiped(tester);
      harness.remote.hold = Completer(); // the sync runs: both wait, a bar says so
      await tester.tap(find.text('Restore to Drive'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Restore to Drive')).onPressed,
        isNull,
      );
      harness.remote.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('removed from Google Drive'), findsNothing);
      expect(harness.remote.texts.keys.where((rel) => rel.endsWith('.md')), hasLength(4));
    });

    testWidgets('Delete here too asks first', (tester) async {
      await wiped(tester);
      await tester.tap(find.text('Delete here too'));
      await tester.pumpAndSettle();
      expect(find.text('Delete 4 notes here too?'), findsOneWidget);
      expect(find.text('A\nB\nC\nD'), findsOneWidget); // which ones, before deciding
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
