import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore_core/notelore_core.dart';

import 'app_test.dart' show choose, connect, phone, pumpApp;
import 'support.dart';

void main() {
  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
  }

  Finder row(String name) => find.byKey(ValueKey('connection-$name'));

  testWidgets('settings: connect another model, switch with one tap, remove one (#362)', (
    tester,
  ) async {
    phone(tester);
    final session = await pumpApp(tester, Harness());
    await connect(tester, key: 'sk-ant');
    await openSettings(tester);
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
      await openSettings(tester);
      await tester.tap(find.descendant(of: row('anthropic'), matching: find.byTooltip('Remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(session.ready, isFalse);
      // Still the app: Settings shows no model, only the way to connect one.
      expect(find.text('Connect another model'), findsOneWidget);
      expect(find.byKey(const Key('model')), findsNothing);
      // The chat asks for a model where the message box was; notes still open.
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
    await openSettings(tester);
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
}
