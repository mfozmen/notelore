import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore_core/notelore_core.dart';

import 'app_test.dart' show connect, phone, pumpApp;
import 'support.dart';

void main() {
  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
  }

  /// Settings → Show advanced settings → Usage: the full page (#294).
  Future<void> openUsage(WidgetTester tester) async {
    await openSettings(tester);
    await tester.scrollUntilVisible(
      find.text('Show advanced settings'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show advanced settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('open-usage')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('open-usage')));
    await tester.pumpAndSettle();
  }

  testWidgets('settings: usage is for advanced users, on its own page (#294)', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    await openSettings(tester);
    expect(find.byKey(const Key('open-usage')), findsNothing); // everyday users see no tokens
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    await openUsage(tester);
    expect(session.advanced, isTrue);
    expect(find.byType(BackButton), findsOneWidget); // a page of its own
    // Remembered: the next start shows it too.
    final again = harness.session();
    await again.load();
    expect(again.advanced, isTrue);
  });

  testWidgets('usage page: both totals, the last days, each model, cost an estimate', (
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
    expect(find.text('This conversation'), findsOneWidget);
    // Plain words first, the technical term as a hint.
    expect(find.text('1,000,000 read · 100,000 written'), findsWidgets);
    expect(find.text('Estimated cost: about \$3.00'), findsWidgets);
    expect(find.text('Last 14 days'), findsOneWidget);
    expect(find.text('1,100,000'), findsOneWidget); // the amount in sight
    expect(find.textContaining('Busiest day'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Last 14 days: 1,100,000 in all')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Claude (Anthropic) · claude-sonnet-5-5'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('By model'), findsOneWidget);
    expect(find.textContaining('estimates from list prices taken on $pricesTaken'), findsOneWidget);
    expect(find.textContaining('ChatGPT plan has no per-token charge'), findsNothing);
  });

  testWidgets('usage page: on the ChatGPT plan, no per-token charge', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    session.usage.record('chatgpt', 'gpt-5', const TokenUsage(10, 1));
    await openUsage(tester);
    await tester.scrollUntilVisible(
      find.textContaining('ChatGPT plan has no per-token charge'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.textContaining('ChatGPT plan has no per-token charge'), findsOneWidget);
  });

  testWidgets('usage page: a local model costs nothing per token; nothing used yet', (
    tester,
  ) async {
    phone(tester);
    final harness = Harness();
    await pumpApp(tester, harness);
    await connect(tester, provider: 'Ollama (local)');
    await openUsage(tester);
    expect(find.text('Nothing yet.'), findsNWidgets(2));
    expect(find.bySemanticsLabel(RegExp('Last 14 days: nothing used')), findsOneWidget);
    expect(find.textContaining('local model has no per-token charge'), findsOneWidget);
  });
}
