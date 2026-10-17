import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/app.dart';
import 'package:notelore/src/session.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'app_test.dart' show phone;
import 'support.dart';

Future<Session> pumpPlanApp(WidgetTester tester, Harness harness) async {
  phone(tester);
  final session = harness.session(owned: false);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpWidget(
    NoteloreApp(
      open: () async {
        await session.load();
        return session;
      },
    ),
  );
  await tester.pumpAndSettle();
  return session;
}

void main() {
  testWidgets('ChatGPT plan: continue with ChatGPT, the welcome, using the plan', (tester) async {
    final launcher = FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
    final harness = Harness(chatGpt: FakeAuth(), answers: ['Merhaba!']);
    await pumpPlanApp(tester, harness);
    // Offered first and selected; no key to paste.
    expect(find.text('ChatGPT plan (OpenAI)'), findsOneWidget);
    expect(find.textContaining('no separate charges'), findsOneWidget);
    // Grouped by how they are paid for (#108); the key and local ones wait
    // under Advanced, closed (#206).
    expect(find.text('Use your plan'), findsOneWidget);
    expect(find.text('Advanced'), findsOneWidget);
    for (final heading in ['API key', 'On this computer']) {
      expect(find.text(heading), findsNothing);
    }
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    for (final heading in ['API key', 'On this computer']) {
      expect(find.text(heading), findsOneWidget);
    }
    expect(find.byKey(const Key('api-key')), findsNothing); // ChatGPT still the choice
    await tester.tap(find.text('Continue with ChatGPT'));
    await tester.pumpAndSettle();
    expect(find.text("You're using your ChatGPT plan"), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text("You're using your ChatGPT plan"), findsNothing);
    expect(find.text('Using ChatGPT plan'), findsOneWidget);
    await tester.tap(find.text('Manage usage'));
    await tester.pumpAndSettle();
    expect(launcher.opened, [chatGptUsageUrl]);
  });

  testWidgets('ChatGPT plan: a failed sign-in is shown on the setup screen', (tester) async {
    final harness = Harness(
      chatGpt: FakeAuth()..failSignIn = const SignInFailed('access_denied', service: 'ChatGPT'),
    );
    await pumpPlanApp(tester, harness);
    await tester.tap(find.text('Continue with ChatGPT'));
    await tester.pumpAndSettle();
    expect(find.text('ChatGPT sign-in failed: access_denied'), findsOneWidget);
    expect(find.text('Continue with ChatGPT'), findsOneWidget);
  });

  testWidgets('other providers show no plan line in the chat', (tester) async {
    final harness = Harness(chatGpt: FakeAuth());
    await pumpPlanApp(tester, harness);
    await tester.tap(find.text('Advanced')); // a key setup still works, from Advanced
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claude (Anthropic)'));
    await tester.pumpAndSettle();
    // Past the grouped list (the key field is a scrollable too: name the list's).
    await tester.scrollUntilVisible(
      find.text('Connect'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(const Key('api-key')), 'k');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Using ChatGPT plan'), findsNothing);
    expect(find.text("You're using your ChatGPT plan"), findsNothing);
  });
}
