import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/setup.dart';
import 'package:notelore_core/notelore_core.dart';

import 'app_test.dart' show phone, pumpApp;
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
}
