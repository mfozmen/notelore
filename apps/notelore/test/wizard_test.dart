import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/setup.dart';
import 'package:notelore_core/notelore_core.dart';

import 'app_test.dart' show phone, pumpApp;
import 'desktop_test.dart' show desktop;
import 'support.dart';

void main() {
  testWidgets('first run: Choose, Connect, Done, each step said, back keeps the choice (#357)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(find.byTooltip('Close'), findsNothing); // the first run cannot be left
    await tester.tap(find.text('Claude (Anthropic)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 3'), findsOneWidget);
    expect(find.byKey(const Key('api-key')), findsOneWidget);
    // Back: the choice is still there. Android's back gesture does the same.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 3'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 3'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('api-key')), 'sk-ant');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    // Connected, but the wizard says so before the chat opens.
    expect(session.ready, isTrue);
    expect(find.text('Step 3 of 3'), findsOneWidget);
    expect(find.textContaining('Claude (Anthropic)'), findsWidgets);
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message')), findsOneWidget); // the chat
  });

  testWidgets('opened from the app: Close leaves it unchanged; Done comes back (#357)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await tester.tap(find.text('Claude (Anthropic)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('api-key')), 'sk-ant');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    final home = tester.element(find.byKey(const Key('message')));
    // Called off: nothing changes.
    final closed = ProviderWizard.open(home, session);
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(await closed, isFalse);
    expect(session.spec!.name, 'anthropic');
    // Finished: back where it was opened, on the new model.
    final done = ProviderWizard.open(home, session);
    await tester.pumpAndSettle();
    await tester.tap(find.text('GPT (OpenAI)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('api-key')), 'sk-oa');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(await done, isTrue);
    expect(session.spec!.name, 'openai');
    expect(find.byKey(const Key('message')), findsOneWidget);
  });

  testWidgets('a refused key is not carried to another provider; no back while checking (#357)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness(rejected: const KeyValidationError('Anthropic rejected the key'))
      ..connectHold = Completer<void>();
    await pumpApp(tester, harness);
    await tester.tap(find.text('Claude (Anthropic)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('api-key')), 'bad');
    await tester.tap(find.text('Connect'));
    await tester.pump();
    // Checking: back does nothing, so a late answer cannot move the step on its own.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Step 2 of 3'), findsOneWidget);
    harness.connectHold!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Anthropic rejected the key'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('GPT (OpenAI)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Anthropic rejected the key'), findsNothing);
  });

  testWidgets('Choose: every option on one screen; the chosen one opens to its details (#358)', (
    tester,
  ) async {
    phone(tester);
    await pumpApp(tester, Harness(chatGpt: FakeAuth()));
    Finder card(String name) => find.byKey(ValueKey('option-$name'));
    Finder on(String name, String text) =>
        find.descendant(of: card(name), matching: find.textContaining(text));
    // All five, each with who it suits and short tags; only the chosen one is
    // tall (pixel fit depends on the font, so the shape is what is checked).
    for (final name in ['chatgpt', 'anthropic', 'openai', 'gemini', 'ollama']) {
      expect(card(name), findsOneWidget, reason: name);
    }
    expect(
      tester.getSize(card('anthropic')).height,
      lessThan(tester.getSize(card('chatgpt')).height),
    );
    expect(find.text('Advanced'), findsNothing); // nothing hidden behind a fold
    expect(on('chatgpt', 'You have ChatGPT Plus or Pro'), findsOneWidget);
    expect(on('ollama', 'Free'), findsWidgets);
    // Details only on the chosen card.
    expect(on('chatgpt', 'Your notes go to OpenAI'), findsOneWidget);
    expect(on('ollama', 'stay on this computer'), findsNothing);
    await tester.ensureVisible(card('ollama'));
    await tester.pumpAndSettle();
    await tester.tap(card('ollama'));
    await tester.pumpAndSettle();
    expect(on('ollama', 'stay on this computer'), findsOneWidget);
    expect(on('chatgpt', 'Your notes go to OpenAI'), findsNothing);
    // The choice is marked by an icon, not by colour alone.
    expect(
      find.descendant(of: card('ollama'), matching: find.byIcon(Icons.check_circle)),
      findsOneWidget,
    );
  });

  testWidgets('Choose on a desk: the action is in view without scrolling (#358)', (tester) async {
    desktop(tester, 1280);
    await pumpApp(tester, Harness(chatGpt: FakeAuth()));
    final button = find.widgetWithText(FilledButton, 'Continue with ChatGPT');
    expect(tester.getRect(button).bottom, lessThanOrEqualTo(1000));
  });

  testWidgets('opened again: the model in use is chosen; a connected one is used at once (#358)', (
    tester,
  ) async {
    phone(tester);
    final session = await pumpApp(tester, Harness());
    await tester.tap(find.text('Claude (Anthropic)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('api-key')), 'sk-ant');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    final home = tester.element(find.byKey(const Key('message')));
    // Another one connected, then the wizard again: GPT, in use, is the choice.
    unawaited(ProviderWizard.open(home, session));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GPT (OpenAI)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('api-key')), 'sk-oa');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    final done = ProviderWizard.open(home, session);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('option-openai')),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
    );
    // Claude is connected: used at once, no key asked again.
    await tester.tap(find.text('Claude (Anthropic)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this model'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('api-key')), findsNothing);
    expect(session.spec!.name, 'anthropic');
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(await done, isTrue);
  });

  testWidgets('Choose: what is already connected says so (#358)', (tester) async {
    phone(tester);
    final session = await pumpApp(tester, Harness());
    await tester.tap(find.text('Claude (Anthropic)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('api-key')), 'sk-ant');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    unawaited(ProviderWizard.open(tester.element(find.byKey(const Key('message'))), session));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('option-anthropic')),
        matching: find.text('Connected'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a connected model whose key was revoked: said, and a new key can go in (#358)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await tester.tap(find.text('Claude (Anthropic)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('api-key')), 'sk-ant');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    harness.rejected = const KeyValidationError('Anthropic rejected the key');
    unawaited(ProviderWizard.open(tester.element(find.byKey(const Key('message'))), session));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this model'));
    await tester.pumpAndSettle();
    // On Connect, the reason on the field, and the field there for a new key.
    final field = find.byKey(const Key('api-key'));
    expect(field, findsOneWidget);
    expect(
      find.descendant(of: field, matching: find.text('Anthropic rejected the key')),
      findsOneWidget,
    );
  });

  testWidgets('Done tries the model once and shows its answer; a failure goes back (#361)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness();
    final hello = Completer<String>();
    harness.provider.tryAnswer = hello.future;
    final session = await pumpApp(tester, harness);
    await tester.tap(find.text('Claude (Anthropic)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('api-key')), 'sk-ant');
    await tester.tap(find.text('Connect'));
    await tester.pump();
    await tester.pump();
    // On its way: said so, and Start waits for it.
    expect(find.text('Saying hello to the model…'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start')).onPressed,
      isNull,
    );
    hello.complete('Hello, ready to take notes.');
    await tester.pumpAndSettle();
    expect(find.text('Hello, ready to take notes.'), findsOneWidget);
    expect(session.usage.device.calls, 0); // a hello is not the conversation's use
    expect(find.textContaining('This one message went to the provider'), findsOneWidget);
    expect(harness.provider.asked, isEmpty); // the test turn is not a chat turn
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('a test turn that fails says why and goes back to Connect (#361)', (tester) async {
    phone(tester);
    final harness = Harness();
    harness.provider.tryAnswer = const HttpError(429, 'quota');
    final session = await pumpApp(tester, harness);
    await tester.tap(find.text('Claude (Anthropic)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('api-key')), 'sk-ant');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('api-key')), findsOneWidget); // back on Connect
    expect(find.byKey(const Key('setup-problem')), findsOneWidget);
    expect(find.textContaining('quota'), findsNothing); // said kindly, not raw
    expect(session.ready, isTrue); // the key itself was fine: it stays connected
  });

  testWidgets('an unexpected error in the test turn never leaves Done spinning (#361)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness();
    harness.provider.tryAnswer = TypeError();
    await pumpApp(tester, harness);
    await tester.tap(find.text('Claude (Anthropic)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('api-key')), 'sk-ant');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('setup-problem')), findsOneWidget); // back on Connect, said
    expect(find.text('Saying hello to the model…'), findsNothing);
  });

  testWidgets('a test turn that never answers stops at 20 s; a late answer is ignored (#376)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness();
    final late = Completer<String>();
    harness.provider.tryAnswer = late.future;
    await pumpApp(tester, harness);
    await tester.tap(find.text('Claude (Anthropic)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('api-key')), 'sk-ant');
    await tester.tap(find.text('Connect'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 19));
    expect(find.text('Saying hello to the model…'), findsOneWidget); // still waiting
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('api-key')), findsOneWidget); // back on Connect
    expect(find.textContaining('did not answer within 20 seconds'), findsOneWidget);
    // Connected again; then the first attempt's answer turns up late.
    harness.provider.tryAnswer = 'Fresh hello.';
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Fresh hello.'), findsOneWidget);
    late.complete('Stale hello.');
    await tester.pumpAndSettle();
    expect(find.text('Stale hello.'), findsNothing);
    expect(find.text('Fresh hello.'), findsOneWidget);
  });
}
