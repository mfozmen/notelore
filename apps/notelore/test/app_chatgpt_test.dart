import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/app.dart';
import 'package:notelore/src/session.dart';
import 'package:notelore/src/strings.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'app_test.dart' show connect, phone;
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
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no separate charges'), findsOneWidget); // its cost, on Connect
    await tester.tap(find.text('Continue with ChatGPT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start')); // the wizard's last step (#357)
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
      await tester.tap(find.text('Claude (Anthropic)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(language == AppLanguage.en ? 'Next' : 'İleri')); // its key steps
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

  testWidgets('a ChatGPT account without Plus or Pro: said plainly, and a free way on (#321)', (
    tester,
  ) async {
    final launcher = FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'Clipboard.getData') return {'text': clipboard};
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final harness = Harness(chatGpt: FakeAuth()..failSignIn = const NoChatGptPlan());
    await pumpPlanApp(tester, harness);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with ChatGPT'));
    await tester.pumpAndSettle();
    final card = find.byKey(const Key('no-chatgpt-plan'));
    expect(
      find.descendant(
        of: card,
        matching: find.text('Your ChatGPT account has no Plus or Pro plan'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.textContaining('improve its products')),
      findsOneWidget,
    );
    expect(find.text('Sign-in did not finish. Please try again.'), findsNothing); // no retry loop
    // One tap: Gemini chosen, and Google AI Studio's key page opens.
    await tester.ensureVisible(find.text('Get a free Gemini key'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get a free Gemini key'));
    await tester.pumpAndSettle();
    expect(launcher.opened, ['https://aistudio.google.com/apikey']);
    final key = find.byKey(const Key('api-key'));
    expect(key, findsOneWidget);
    // Back in the app with the key copied: it goes into the box, said so; it
    // connects only on Connect.
    clipboard = 'AIza${'x' * 35}';
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(key).controller!.text, clipboard);
    expect(find.textContaining('pasted from the clipboard'), findsOneWidget);
    expect(find.byKey(const Key('message')), findsNothing); // still in setup
  });

  testWidgets('no plan: the clipboard is read once, only for a key; another provider clears it', (
    tester,
  ) async {
    UrlLauncherPlatform.instance = FakeLauncher();
    String? clipboard;
    var reads = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method != 'Clipboard.getData') return null;
      reads++;
      return {'text': clipboard};
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    Future<void> comeBack() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    }

    await pumpPlanApp(tester, Harness(chatGpt: FakeAuth()..failSignIn = const NoChatGptPlan()));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with ChatGPT'));
    await tester.pumpAndSettle();
    final card = find.byKey(const Key('no-chatgpt-plan'));
    expect(card, findsOneWidget);
    // Back, and another provider chosen: the card is about ChatGPT, so it goes.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claude (Anthropic)'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(card, findsNothing);
    await comeBack();
    expect(reads, 0); // never asked for a key: the clipboard is not read
    await tester.pageBack();
    await tester.pumpAndSettle();
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('ChatGPT plan (OpenAI)'), -200, scrollable: list);
    await tester.tap(find.text('ChatGPT plan (OpenAI)'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with ChatGPT'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Get a free Gemini key'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get a free Gemini key'));
    await tester.pumpAndSettle();
    // Something else on the clipboard is left alone, and it is read only once.
    clipboard = 'a shopping list';
    await comeBack();
    clipboard = 'AIza${'x' * 35}';
    await comeBack();
    expect(reads, 1);
    expect(tester.widget<TextField>(find.byKey(const Key('api-key'))).controller!.text, isEmpty);
  });

  testWidgets('ChatGPT plan: a failed sign-in is shown on the setup screen', (tester) async {
    final harness = Harness(
      chatGpt: FakeAuth()..failSignIn = const SignInFailed('access_denied', service: 'ChatGPT'),
    );
    await pumpPlanApp(tester, harness);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
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
    await connect(tester, key: 'k');
    expect(find.text('Using ChatGPT plan'), findsNothing);
    expect(find.text("You're using your ChatGPT plan"), findsNothing);
  });
}
