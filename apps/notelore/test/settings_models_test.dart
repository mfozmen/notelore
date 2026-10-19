import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore_core/notelore_core.dart';

import 'app_chatgpt_test.dart' show pumpPlanApp;
import 'app_test.dart' show choose, connect, phone, pumpApp;
import 'support.dart';

void main() {
  Future<void> openModel(WidgetTester tester) => openSettings(tester, 'Model');

  Finder row(String name) => find.byKey(ValueKey('connection-$name'));

  testWidgets('settings: connect another model, switch with one tap, remove one (#362)', (
    tester,
  ) async {
    phone(tester);
    final session = await pumpApp(tester, Harness());
    await connect(tester, key: 'sk-ant');
    await openModel(tester);
    expect(find.text('Connected models'), findsOneWidget);
    expect(row('anthropic'), findsOneWidget);
    // Another model, through the wizard: back in Settings on it.
    await tester.tap(find.text('Connect another model'));
    await tester.pumpAndSettle();
    await choose(tester, 'GPT (OpenAI)');
    await tester.enterText(find.byKey(const Key('api-key')), 'sk-oa');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(session.spec!.name, 'openai');
    expect(row('openai'), findsOneWidget);
    expect(
      find.descendant(of: row('openai'), matching: find.byIcon(Icons.check_circle)),
      findsOneWidget,
    );
    // One tap: back on Claude, said briefly.
    await tester.tap(row('anthropic'));
    await tester.pumpAndSettle();
    expect(session.spec!.name, 'anthropic');
    expect(find.text('Now using Claude (Anthropic)'), findsOneWidget);
    // Remove one: asked first; called off, nothing goes.
    await tester.tap(find.descendant(of: row('openai'), matching: find.byTooltip('Remove')));
    await tester.pumpAndSettle();
    expect(find.text('Remove GPT (OpenAI)?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(row('openai'), findsOneWidget);
    await tester.tap(find.descendant(of: row('openai'), matching: find.byTooltip('Remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(row('openai'), findsNothing);
    expect(session.spec!.name, 'anthropic');
  });

  testWidgets(
    'settings: removing the model in use leaves none; the app stays, the chat asks for one (#363)',
    (tester) async {
      phone(tester);
      final session = await pumpApp(tester, Harness(answers: ['Saved.']));
      await connect(tester, key: 'sk-ant');
      await openModel(tester);
      await tester.tap(find.descendant(of: row('anthropic'), matching: find.byTooltip('Remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(session.ready, isFalse);
      // Still the app: Settings shows no model, only the way to connect one.
      expect(find.text('Connect another model'), findsOneWidget);
      expect(find.byKey(const Key('model')), findsNothing);
      // The chat asks for a model where the message box was; notes still open.
      await tester.pageBack(); // the phone's Settings page
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('message')), findsNothing);
      expect(find.text('Connect a model to start'), findsOneWidget);
      expect(find.byTooltip('Resend'), findsNothing); // nothing to send it with
      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();
      expect(find.text('Notes'), findsWidgets);
      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();
      // Connect from the chat: the wizard, then back with the message box.
      await tester.tap(find.widgetWithText(FilledButton, 'Connect a model'));
      await tester.pumpAndSettle();
      await choose(tester, 'GPT (OpenAI)');
      await tester.enterText(find.byKey(const Key('api-key')), 'sk-oa');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('message')), findsOneWidget);
    },
  );

  testWidgets('settings: a model whose key is gone says so when chosen (#362)', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'sk-ant');
    await openModel(tester);
    await tester.tap(find.text('Connect another model'));
    await tester.pumpAndSettle();
    await choose(tester, 'GPT (OpenAI)');
    await tester.enterText(find.byKey(const Key('api-key')), 'sk-oa');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    harness.rejected = const KeyValidationError('Anthropic rejected the key');
    await tester.tap(row('anthropic'));
    await tester.pumpAndSettle();
    expect(session.spec!.name, 'openai'); // nothing changed
    expect(find.text('Anthropic rejected the key'), findsOneWidget);
    // Offline: said, with what to do.
    harness.rejected = const TransientValidationError('Anthropic is not reachable');
    await tester.tap(row('anthropic'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Check the connection'), findsOneWidget);
    // Its key lost from the keystore since the list showed it: no crash, a plain word.
    harness.rejected = null;
    await const FlutterSecureStorage().delete(key: 'notelore.anthropic.api_key');
    await tester.tap(row('anthropic'));
    await tester.pumpAndSettle();
    expect(find.text('Sign-in did not finish. Please try again.'), findsOneWidget);
    expect(session.spec!.name, 'openai');
  });

  testWidgets('settings: a removal that fails says so; no removal while switching (#369)', (
    tester,
  ) async {
    final auth = FakeAuth();
    final harness = Harness(chatGpt: auth);
    await pumpPlanApp(tester, harness);
    await tester.tap(find.text('Continue with ChatGPT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    await openModel(tester);
    await tester.tap(find.text('Connect another model'));
    await tester.pumpAndSettle();
    await choose(tester, 'Claude (Anthropic)');
    await tester.enterText(find.byKey(const Key('api-key')), 'sk-ant');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    // The sign-out fails: said, and the row stays.
    auth.failSignOut = Exception('keystore locked');
    await tester.tap(find.descendant(of: row('chatgpt'), matching: find.byTooltip('Remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Could not remove it. Please try again.'), findsOneWidget);
    expect(row('chatgpt'), findsOneWidget);
    // While a switch is checked, nothing can be removed.
    await tester.tap(row('chatgpt'));
    await tester.pumpAndSettle();
    harness.connectHold = Completer<void>();
    await tester.tap(row('anthropic')); // its key is checked again
    await tester.pump();
    for (final remove in find.byTooltip('Remove').evaluate()) {
      final button = remove.findAncestorWidgetOfExactType<IconButton>()!;
      expect(button.onPressed, isNull);
    }
    harness.connectHold!.complete();
    await tester.pumpAndSettle();
  });
}
