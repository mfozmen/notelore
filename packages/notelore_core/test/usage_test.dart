import 'dart:convert';
import 'dart:io';

import 'package:notelore_core/src/providers/base.dart';
import 'package:notelore_core/src/store/format.dart' show parseIsoDate;
import 'package:notelore_core/src/usage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _Fake implements LlmProvider {
  _Fake(this.usage);

  final TokenUsage? usage;

  @override
  String get model => 'claude-sonnet-5-5';

  @override
  Future<AgentResponse> turn(String system, List<Message> messages, List<Tool> tools) async =>
      AgentResponse(const [], 'end_turn', usage: usage);
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('notelore_usage_'));
  tearDown(() => dir.deleteSync(recursive: true));

  String file() => p.join(dir.path, 'state', 'usage.json');

  test('a count adds up calls and tokens; a call without usage is counted apart', () {
    final count = const UsageCount()
        .add(const TokenUsage(100, 20))
        .add(null)
        .add(const TokenUsage(50, 5));
    expect((count.calls, count.unreported, count.input, count.output), (3, 1, 150, 25));
    final both = count + const UsageCount(calls: 1, input: 1, output: 1);
    expect((both.calls, both.unreported, both.input, both.output), (4, 1, 151, 26));
  });

  group('summary', () {
    test('cost is the tokens at the table price, as an estimate', () {
      final summary = summarize({
        'anthropic/claude-sonnet-5-5': const UsageCount(calls: 2, input: 1000000, output: 100000),
      });
      expect((summary.calls, summary.input, summary.output), (2, 1000000, 100000));
      expect(summary.cost, closeTo(2 + 1, 1e-9)); // $2 in, $10 out per million
      expect(summary.tokensKnown, isTrue);
      expect(summary.plan, isFalse);
    });

    test('the ChatGPT plan and a local model cost nothing per token', () {
      final summary = summarize({
        'chatgpt/gpt-5': const UsageCount(calls: 1, input: 10, output: 1),
        'ollama/llama3.2': const UsageCount(calls: 1, input: 10, output: 1),
        'device/qwen3-4b-instruct-2507': const UsageCount(calls: 1, input: 10, output: 1),
      });
      expect(summary.cost, 0);
      expect(summary.plan, isTrue);
      expect(summary.billed, isFalse); // nothing per token at all (#436)
      expect(
        summarize({
          'chatgpt/gpt-5': const UsageCount(calls: 1, input: 10, output: 1),
          'anthropic/claude-sonnet-5-5': const UsageCount(calls: 1, input: 10, output: 1),
        }).billed,
        isTrue,
      );
    });

    test('an unknown price or a call without usage leaves the cost unknown, never guessed', () {
      expect(
        summarize({'openai/some-new-model': const UsageCount(calls: 1, input: 5, output: 5)}).cost,
        isNull,
      );
      final partly = summarize({
        'gemini/gemini-2.5-flash': const UsageCount(calls: 2, unreported: 1, input: 5, output: 5),
      });
      expect(partly.cost, isNull);
      expect(partly.tokensKnown, isTrue); // one call did report
      final none = summarize({
        'gemini/gemini-2.5-flash': const UsageCount(calls: 1, unreported: 1),
      });
      expect(none.tokensKnown, isFalse);
    });

    test('nothing used yet', () {
      final empty = summarize({});
      expect((empty.calls, empty.cost, empty.tokensKnown), (0, 0, false));
    });

    test('every price in the table is per million tokens and dated', () {
      expect(prices, isNotEmpty);
      expect(parseIsoDate(pricesTaken), isNotNull);
      for (final price in prices.values) {
        expect(price.input, greaterThan(0));
        expect(price.output, greaterThanOrEqualTo(price.input));
      }
    });
  });

  group('meter', () {
    test('records each call per conversation and on this device, kept on disk', () async {
      final meter = UsageMeter(file());
      final provider = MeteredProvider(_Fake(const TokenUsage(10, 2)), 'anthropic', meter);
      expect(provider.model, 'claude-sonnet-5-5');
      await provider.turn('', [], []);
      await provider.turn('', [], []);
      expect(meter.conversation.input, 20);
      expect(meter.device.calls, 2);
      meter.newConversation();
      expect(meter.conversation.calls, 0);
      expect(meter.device.calls, 2);
      final again = UsageMeter(file()); // the app started again
      expect((again.device.calls, again.device.input, again.device.output), (2, 20, 4));
      expect(again.conversation.calls, 0);
      final saved = jsonDecode(File(file()).readAsStringSync()) as Map<String, Object?>;
      expect(saved.keys, ['anthropic/claude-sonnet-5-5']);
    });

    test('a call without usage counts as a call with no tokens', () async {
      final meter = UsageMeter(file());
      await MeteredProvider(_Fake(null), 'gemini', meter).turn('', [], []);
      expect((meter.device.calls, meter.device.unreported), (1, 1));
    });

    test('a total that cannot be saved never fails the answer', () async {
      Directory(p.join(file(), 'blocker')).createSync(recursive: true); // the file is a folder
      final meter = UsageMeter(file());
      final response = await MeteredProvider(
        _Fake(const TokenUsage(1, 1)),
        'x',
        meter,
      ).turn('', [], []);
      expect(response.usage, isNotNull);
      expect(meter.device.calls, 1); // still counted while the app runs
    });

    test('each day keeps its own count, for the last days chart (#294)', () {
      var day = DateTime(2026, 10, 16);
      final meter = UsageMeter(file(), today: () => day);
      meter.record('anthropic', 'claude-sonnet-5-5', const TokenUsage(10, 2));
      day = DateTime(2026, 10, 18);
      meter.record('anthropic', 'claude-sonnet-5-5', const TokenUsage(5, 1));
      meter.record('gemini', 'gemini-2.5-flash', const TokenUsage(3, 3));
      final days = UsageMeter(file(), today: () => day).lastDays(3); // kept on disk
      expect(
        [for (final d in days) d.day],
        [DateTime(2026, 10, 16), DateTime(2026, 10, 17), DateTime(2026, 10, 18)],
      );
      expect([for (final d in days) d.count.input + d.count.output], [12, 0, 12]);
      // Per model, over the whole device.
      final models = meter.byModel;
      expect(models.keys, ['anthropic/claude-sonnet-5-5', 'gemini/gemini-2.5-flash']);
      expect(models['anthropic/claude-sonnet-5-5']!.input, 15);
      expect(models['gemini/gemini-2.5-flash']!.cost, closeTo((3 * 0.30 + 3 * 2.50) / 1e6, 1e-12));
    });

    test('days older than ninety are dropped; a damaged day file starts again', () {
      var day = DateTime(2026, 1, 1);
      final meter = UsageMeter(file(), today: () => day);
      meter.record('x', 'm', const TokenUsage(1, 1));
      day = DateTime(2026, 6, 1);
      meter.record('x', 'm', const TokenUsage(1, 1));
      final saved = File(p.join(dir.path, 'state', 'usage-days.json')).readAsStringSync();
      expect(saved, isNot(contains('2026-01-01')));
      File(p.join(dir.path, 'state', 'usage-days.json')).writeAsStringSync('{broken');
      expect(UsageMeter(file(), today: () => day).lastDays(1).single.count.calls, 0);
    });

    test('a damaged file starts the device total again instead of failing', () {
      File(file())
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{not json');
      expect(UsageMeter(file()).device.calls, 0);
      File(file()).writeAsStringSync('{"anthropic/m": {"calls": "x"}, "odd": 3}');
      expect(UsageMeter(file()).device.calls, 0);
    });
  });

  group('turns and ranges, for the usage page (#481)', () {
    const sonnet = 'anthropic/claude-sonnet-5-5';
    const flash = 'gemini/gemini-2.5-flash';

    test('a turn counts its answer time, tool calls, notes written and errors', () {
      const none = TurnCount();
      final one = none.add(
        took: const Duration(milliseconds: 1500),
        toolCalls: 3,
        wrote: true,
        failed: false,
      );
      final two = one.add(
        took: const Duration(seconds: 2),
        toolCalls: 0,
        wrote: false,
        failed: true,
      );
      expect((two.turns, two.failed, two.toolCalls, two.wrote, two.millis), (2, 1, 3, 1, 3500));
      expect(two.averageAnswer, const Duration(milliseconds: 1750));
      expect(none.averageAnswer, Duration.zero);
      expect(two.toolCallsPerTurn, 1.5);
      expect(none.toolCallsPerTurn, 0);
      expect(two.errorShare, 0.5);
      expect(none.errorShare, 0);
      expect(one + one, TurnCount.fromJson((one + one).toJson()));
      expect(TurnCount.fromJson(const {'turns': 'x'}), const TurnCount()); // damaged: none
    });

    test('a range sums each model by day; all time is the whole device', () {
      var day = DateTime(2026, 10, 1);
      final meter = UsageMeter(file(), today: () => day);
      meter
        ..record('anthropic', 'claude-sonnet-5-5', const TokenUsage(10, 2))
        ..recordTurn(
          'anthropic',
          'claude-sonnet-5-5',
          took: const Duration(seconds: 1),
          toolCalls: 2,
          wrote: true,
          failed: false,
        );
      day = DateTime(2026, 10, 18);
      meter
        ..record('anthropic', 'claude-sonnet-5-5', const TokenUsage(5, 1))
        ..record('gemini', 'gemini-2.5-flash', const TokenUsage(3, 3))
        ..recordTurn(
          'gemini',
          'gemini-2.5-flash',
          took: const Duration(seconds: 3),
          toolCalls: 1,
          wrote: false,
          failed: true,
        );
      final again = UsageMeter(file(), today: () => day); // kept on disk
      final week = again.tokensIn(UsageRange.week);
      expect(week.keys, unorderedEquals([sonnet, flash]));
      expect(week[sonnet]!.input, 5); // the 1st is outside the week
      expect(again.tokensIn(UsageRange.all)[sonnet]!.input, 15);
      expect(again.turnsIn(UsageRange.week).keys, [flash]);
      expect(again.turnsIn(UsageRange.all)[sonnet]!.toolCalls, 2);
      expect(again.turnsIn(UsageRange.month)[sonnet]!.wrote, 1);
      expect(UsageRange.values.map((r) => r.days), [7, 14, 30, null]);
      // The chart: each day, each model apart.
      final days = again.daysByModel(UsageRange.twoWeeks);
      expect(days, hasLength(14));
      expect(days.last.day, DateTime(2026, 10, 18));
      expect(days.last.byModel.keys, unorderedEquals([sonnet, flash]));
      expect(days.first.byModel, isEmpty);
      // All time charts the days kept.
      expect(again.daysByModel(UsageRange.all), hasLength(90));
    });

    test('a damaged turns file starts again', () {
      final meter = UsageMeter(file());
      meter.recordTurn('x', 'm', took: Duration.zero, toolCalls: 0, wrote: false, failed: false);
      File(p.join(dir.path, 'state', 'usage-turns.json')).writeAsStringSync('{broken');
      expect(UsageMeter(file()).turnsIn(UsageRange.all), isEmpty);
    });
  });
}
