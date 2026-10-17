import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore_core/notelore_core.dart';

import 'app_test.dart' show connect, phone, pumpApp;
import 'support.dart';

void main() {
  Future<void> openUsage(WidgetTester tester) async {
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('On this device'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('settings: what this conversation and this device used, cost an estimate', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    session.usage
      ..record('anthropic', 'claude-sonnet-5-5', const TokenUsage(1000000, 100000))
      ..record('anthropic', 'claude-sonnet-5-5', const TokenUsage(0, 0));
    await openUsage(tester);
    expect(find.text('Usage'), findsWidgets);
    expect(find.text('This conversation'), findsOneWidget);
    expect(find.text('Tokens: 1,000,000 in, 100,000 out'), findsNWidgets(2));
    expect(find.text('Estimated cost: about \$3.00'), findsNWidgets(2));
    expect(find.textContaining('estimates from list prices taken on $pricesTaken'), findsOneWidget);
    expect(find.textContaining('ChatGPT plan has no per-token charge'), findsNothing);
  });

  testWidgets('settings: on the ChatGPT plan, no per-token charge', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    session.usage.record('chatgpt', 'gpt-5', const TokenUsage(10, 1));
    await openUsage(tester);
    expect(find.textContaining('ChatGPT plan has no per-token charge'), findsOneWidget);
  });

  testWidgets('settings: a local model costs nothing per token; nothing used yet', (tester) async {
    phone(tester);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, provider: 'Ollama (local)');
    await openUsage(tester);
    expect(find.text('Nothing yet.'), findsNWidgets(2));
    expect(find.textContaining('local model has no per-token charge'), findsOneWidget);
  });
}
