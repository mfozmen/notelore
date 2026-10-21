import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/setup.dart';
import 'package:notelore/src/theme.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'app_test.dart' show choose, phone, pumpApp;
import 'desktop_test.dart' show desktop;
import 'support.dart';

void main() {
  for (final wide in [false, true]) {
    testWidgets('the step bar spans the content, on a ${wide ? 'desk' : 'phone'} (#508)', (
      tester,
    ) async {
      wide ? desktop(tester, 1280) : phone(tester);
      await pumpApp(tester, Harness());
      expect(
        tester.getTopLeft(find.byKey(const Key('step-bar'))).dx,
        tester.getTopLeft(find.text('Choose a model provider')).dx,
      );
      // The step's words start the line, next to the button's place.
      expect(
        tester.getTopLeft(find.text('Step 1 of 3')).dx,
        lessThan(tester.getCenter(find.byKey(const Key('step-bar'))).dx),
      );
      // Its right end too: the step's words sit above it, not beside it.
      expect(
        tester.getTopRight(find.byKey(const Key('step-bar'))).dx,
        tester.getTopRight(find.byKey(const ValueKey('option-anthropic'))).dx,
      );
    });
  }

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
    // Opened, its details say what the tags said: nothing twice (#508).
    expect(on('ollama', 'Stays on this computer'), findsNothing);
    expect(on('ollama', 'Free'), findsOneWidget);
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
    expect(find.byKey(const Key('hello-bubble')), findsNothing); // a status is never a bubble
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start')).onPressed,
      isNull,
    );
    hello.complete('Hello, ready to take notes.');
    await tester.pumpAndSettle();
    expect(find.text('Hello, ready to take notes.'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('hello-bubble'))).width,
      lessThanOrEqualTo(tester.getSize(find.byType(Scaffold)).width * 0.85),
    );
    // The model's words read as an answer, not as a field; the usage page says what
    // it cost (#508).
    expect(
      find.ancestor(of: find.text('Hello, ready to take notes.'), matching: find.byType(Card)),
      findsNothing,
    );
    expect(session.usage.device.calls, 0); // a hello is not the conversation's use
    expect(find.textContaining('This one message went to the provider'), findsNothing);
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

  testWidgets('Connect: back from the key page, a copied key of that provider goes in (#359)', (
    tester,
  ) async {
    phone(tester);
    final launcher = FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      return call.method == 'Clipboard.getData' ? {'text': clipboard} : null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    Future<void> comeBack(String copied) async {
      clipboard = copied;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    }

    await pumpApp(tester, Harness());
    await tester.tap(find.text('Claude (Anthropic)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    final key = find.byKey(const Key('api-key'));
    // Back without opening the page: the clipboard is not looked at.
    await comeBack('sk-ant-api03-${'a' * 80}');
    expect(tester.widget<TextField>(key).controller!.text, isEmpty);
    await tester.tap(find.text('Open console.anthropic.com'));
    await tester.pumpAndSettle();
    expect(launcher.opened, ['https://console.anthropic.com/settings/keys']);
    // Something that is not an Anthropic key stays out.
    await comeBack('AIza${'x' * 35}');
    expect(tester.widget<TextField>(key).controller!.text, isEmpty);
    await tester.tap(find.text('Open console.anthropic.com'));
    await tester.pumpAndSettle();
    await comeBack('sk-ant-api03-${'a' * 80}');
    expect(tester.widget<TextField>(key).controller!.text, 'sk-ant-api03-${'a' * 80}');
    expect(find.textContaining('pasted from the clipboard'), findsOneWidget);
  });

  testWidgets('Connect on a phone: an edge over the pinned action while more is below (#352)', (
    tester,
  ) async {
    phone(tester);
    await pumpApp(tester, Harness());
    // Choose is a long list: more below, so the edge shows.
    expect(find.byKey(const Key('action-edge')), findsOneWidget);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -5000));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('action-edge')), findsNothing); // at the end: none
  });

  testWidgets(
    'a short desk window: the list scrolls below the header, its bar in a gutter (#472)',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1056, 540)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpApp(tester, Harness());
      final card = find.byKey(const Key('setup-card'));
      final list = find.descendant(of: card, matching: find.byType(SingleChildScrollView));
      // The scrollbar has its own gutter: the cards never sit under it.
      expect(
        tester.widget<SingleChildScrollView>(list).padding,
        const EdgeInsets.only(right: Gap.m),
      );
      expect(find.byKey(const Key('header-edge')), findsNothing);
      expect(find.byKey(const Key('action-edge')), findsOneWidget); // more below
      // Scrolled: an edge under the header, so the clipped text reads as scrolled away.
      await tester.drag(list, const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('header-edge')), findsOneWidget);
      await tester.drag(list, const Offset(0, -5000));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('action-edge')), findsNothing);
    },
  );

  testWidgets('on this device: a checked download, then the model answers here (#328)', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness()..deviceModels = true;
    harness.pages['https://models.test/q.gguf'] = 'model bytes';
    harness.deviceEngine.answers.add({
      'message': {'content': 'Hello from this phone.'},
    });
    final session = await pumpApp(tester, harness);
    await choose(tester, 'On this device (Qwen3 4B)');
    expect(find.textContaining('2.5 GB download'), findsWidgets);
    await tester.tap(find.text('Download and connect'));
    // The download is real file work, outside the fake clock.
    await settleUntil(tester, () => session.ready);
    expect(session.deviceModel.ready, isTrue);
    expect(session.spec?.name, 'device');
    expect(find.text('Step 3 of 3'), findsOneWidget);
    expect(find.textContaining('Hello from this phone.'), findsOneWidget);
  });

  testWidgets('on this device: a download that fails says so and stays on Connect', (tester) async {
    phone(tester);
    final harness = Harness()..deviceModels = true;
    harness.pages['https://models.test/q.gguf'] = 'broken bytes';
    final session = await pumpApp(tester, harness);
    await choose(tester, 'On this device (Qwen3 4B)');
    await tester.tap(find.text('Download and connect'));
    await settleUntil(tester, () => find.textContaining('did not finish').evaluate().isNotEmpty);
    expect(session.ready, isFalse);
    expect(find.text('Step 2 of 3'), findsOneWidget);
    // Why, in plain words, and that a retry goes on from where it stopped (#508).
    expect(
      find.text('The download did not finish. Try again in a while. It goes on where it stopped.'),
      findsOneWidget,
    );
    // The button says what it does now.
    expect(find.text('Resume download'), findsOneWidget);
  });

  testWidgets('on this device: Back works during the download, and nothing connects behind it', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness()..deviceModels = true;
    final served = Completer<String>();
    harness.pages['https://models.test/q.gguf'] = served.future;
    final session = await pumpApp(tester, harness);
    await choose(tester, 'On this device (Qwen3 4B)');
    await tester.tap(find.text('Download and connect'));
    await tester.pump();
    expect(session.deviceProgress, isNotNull);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 3'), findsOneWidget);
    served.complete('model bytes');
    await settleUntil(tester, () => session.deviceModel.ready);
    expect(session.spec, isNull); // left before it finished: nothing chosen behind the user's back
    expect(find.text('Step 1 of 3'), findsOneWidget);
  });

  testWidgets('step numbers grow with the text size (#352)', (tester) async {
    phone(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, Harness());
    await tester.ensureVisible(find.text('Claude (Anthropic)')); // big text: further down
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claude (Anthropic)'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(tester.widget<CircleAvatar>(find.byType(CircleAvatar).first).radius, 24);
  });
}
