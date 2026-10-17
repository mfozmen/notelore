import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/app.dart';
import 'package:notelore/src/session.dart';
import 'package:notelore/src/strings.dart';
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
    // The desktop runs local models: Advanced says so (#304).
    expect(find.text('Your own API key, or a model on this computer.'), findsOneWidget);
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

  for (final language in [AppLanguage.en, AppLanguage.tr]) {
    testWidgets('setup on a phone never speaks of a computer or of clicking (#304, $language)', (
      tester,
    ) async {
      final harness = Harness(chatGpt: FakeAuth(), localModels: false);
      final session = await pumpPlanApp(tester, harness);
      session.setLanguage(language);
      await tester.pumpAndSettle();
      final advanced = language == AppLanguage.en ? 'Advanced' : 'Gelişmiş';
      expect(
        find.text(
          language == AppLanguage.en ? 'Use your own API key.' : 'Kendi API anahtarını kullan.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text(advanced));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Claude (Anthropic)')); // its key steps show
      await tester.pumpAndSettle();
      final shown = [
        for (final text in tester.widgetList<Text>(find.byType(Text)))
          text.data ?? text.textSpan?.toPlainText() ?? '',
      ].join('\n');
      for (final desktop in ['computer', 'bilgisayar', 'Click', 'tıkla']) {
        expect(shown, isNot(contains(desktop)), reason: desktop);
      }
    });
  }

  testWidgets('ChatGPT plan: a failed sign-in is shown on the setup screen', (tester) async {
    final harness = Harness(
      chatGpt: FakeAuth()..failSignIn = const SignInFailed('access_denied', service: 'ChatGPT'),
    );
    await pumpPlanApp(tester, harness);
    await tester.tap(find.text('Continue with ChatGPT'));
    await tester.pumpAndSettle();
    expect(find.text('Sign-in did not finish. Please try again.'), findsOneWidget);
    expect(find.textContaining('access_denied'), findsNothing); // no raw codes (#302)
    expect(find.text('Continue with ChatGPT'), findsOneWidget);
    // A raw HTTP answer is not shown either.
    harness.chatGpt!.failSignIn = const HttpError(400, '{"error": "invalid_grant"}');
    await tester.tap(find.text('Continue with ChatGPT'));
    await tester.pumpAndSettle();
    expect(find.text('Sign-in did not finish. Please try again.'), findsOneWidget);
    expect(find.textContaining('invalid_grant'), findsNothing);
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
