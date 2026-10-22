import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/strings.dart';
import 'package:notelore_core/notelore_core.dart';

import 'app_test.dart' show connect, phone, pumpApp;
import 'support.dart';

void main() {
  Future<void> openAdvanced(WidgetTester tester) => openSettings(tester, 'About');

  /// Settings > About > Show advanced settings > Usage: the full page (#294).
  Future<void> openUsage(WidgetTester tester) async {
    await openAdvanced(tester);
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
    await openAdvanced(tester);
    expect(find.byKey(const Key('open-usage')), findsNothing); // everyday users see no tokens
    await tester.pageBack();
    await tester.pumpAndSettle();
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
    // The amount in sight with its unit, once for the conversation and once for
    // the range: the chart below does not say it a third time (#508).
    expect(find.text('1,100,000 tokens'), findsNWidgets(2));
    expect(find.textContaining(RegExp(r'^Busiest day: .*tokens$')), findsOneWidget);
    expect(find.textContaining('Busiest day'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Last 14 days: 1,100,000 tokens in all')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Claude (Anthropic) · claude-sonnet-5-5'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('By model'), findsOneWidget);
    expect(find.textContaining('estimates from list prices taken on $pricesTaken'), findsOneWidget);
    expect(find.textContaining('ChatGPT plan has no per-token charge'), findsNothing);
  });

  testWidgets(
    'usage page: a range, each model stacked by day, its share, and the messages (#481)',
    (tester) async {
      phone(tester);
      final harness = Harness();
      final session = await pumpApp(tester, harness);
      await connect(tester, key: 'k');
      session.usage
        ..record('anthropic', 'claude-sonnet-5-5', const TokenUsage(600, 150))
        ..record('gemini', 'gemini-2.5-flash', const TokenUsage(200, 50))
        ..recordTurn(
          'anthropic',
          'claude-sonnet-5-5',
          took: const Duration(milliseconds: 1500),
          toolCalls: 3,
          wrote: true,
          failed: false,
        )
        ..recordTurn(
          'anthropic',
          'claude-sonnet-5-5',
          took: const Duration(milliseconds: 2500),
          toolCalls: 1,
          wrote: false,
          failed: true,
        );
      await openUsage(tester);
      expect(find.text('Last 14 days'), findsOneWidget); // the range shown first
      await tester.tap(find.text('7 days'));
      await tester.pumpAndSettle();
      expect(find.text('Last 7 days'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Last 7 days: 1,000 tokens in all')), findsOneWidget);
      // A tap on a day splits it by model, in words, not by colour alone.
      expect(find.text('Tap a day to see each model.'), findsOneWidget);
      final chart = find.byKey(const Key('usage-chart'));
      await tester.tapAt(tester.getBottomRight(chart) - const Offset(2, 30)); // today
      await tester.pumpAndSettle();
      expect(find.text('750'), findsOneWidget);
      expect(find.text('250'), findsOneWidget);
      // The same day again lets it go; a drag picks a day too, an empty one says so.
      await tester.tapAt(tester.getBottomRight(chart) - const Offset(2, 30));
      await tester.pumpAndSettle();
      expect(find.text('Tap a day to see each model.'), findsOneWidget);
      await tester.drag(chart, const Offset(-60, 0));
      await tester.pumpAndSettle();
      expect(find.text('Nothing yet.'), findsOneWidget);
      // Each model's share, with its own tokens and cost.
      await tester.scrollUntilVisible(
        find.text('Messages'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
      expect(find.text('Estimated cost: about \$0.0027'), findsOneWidget); // 600 read, 150 written
      for (final (label, value) in [
        ('Messages', '2'),
        ('Model calls per message', '1.0'),
        ('Tokens per message', '500'),
        ('Average answer time', '2.0 s'),
        ('Tool calls', '4'),
        ('Messages that wrote notes', '1'),
        ('Messages with an error', '50%'),
      ]) {
        expect(
          find.descendant(of: find.byKey(Key('stat-$label')), matching: find.text(value)),
          findsOneWidget,
          reason: label,
        );
      }
      // All time: the totals of everything, the chart of the days kept.
      await tester.scrollUntilVisible(
        find.text('All'),
        -300,
        scrollable: find.byType(Scrollable).last,
      );
      // Thirty bars are too narrow for day numbers: the first day and today are named.
      await tester.tap(find.text('30 days'));
      await tester.pumpAndSettle();
      expect(find.textContaining(RegExp(r'^[A-Z][a-z]{2} \d{1,2}$')), findsAtLeastNWidgets(2));
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.text('All time'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('The chart shows the last 90 days'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
    },
  );

  testWidgets('usage page: in Turkish, the share and the time read as Turkish', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    session
      ..setLanguage(AppLanguage.tr)
      ..setAdvanced(true);
    session.usage
      ..record('anthropic', 'claude-sonnet-5-5', const TokenUsage(1, 0))
      ..record('gemini', 'gemini-2.5-flash', const TokenUsage(999, 0))
      ..recordTurn(
        'anthropic',
        'claude-sonnet-5-5',
        took: const Duration(milliseconds: 1250),
        toolCalls: 0,
        wrote: false,
        failed: false,
      );
    await tester.pumpAndSettle();
    await openSettings(tester, session.strings.aboutSection);
    await tester.ensureVisible(find.byKey(const Key('open-usage')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-usage')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Mesajlar'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('%100'), findsOneWidget);
    expect(find.text('<%1'), findsOneWidget);
    expect(find.text('1,3 sn'), findsOneWidget);
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
    expect(find.text('Usage shows here after your first message.'), findsOneWidget);
    expect(find.textContaining('local model has no per-token charge'), findsOneWidget);
  });

  testWidgets('usage page: with big text a title keeps its words whole (#508)', (tester) async {
    phone(tester);
    final harness = Harness();
    final session = await pumpApp(tester, harness);
    await connect(tester, key: 'k');
    session.usage.record('anthropic', 'claude-sonnet-5-5', const TokenUsage(1000000, 100000));
    await openUsage(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    for (final title in ['This conversation', 'Last 14 days']) {
      final text = tester.renderObject<RenderBox>(find.text(title));
      // Laid out at least as wide as its longest word: never cut inside one.
      final longest = title.split(' ').map((w) => w.length).reduce((a, b) => a > b ? a : b);
      expect(text.size.width, greaterThan(longest * 2 * 8.0), reason: title);
    }
  });
}
