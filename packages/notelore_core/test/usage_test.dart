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
      });
      expect(summary.cost, 0);
      expect(summary.plan, isTrue);
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

    test('a damaged file starts the device total again instead of failing', () {
      File(file())
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{not json');
      expect(UsageMeter(file()).device.calls, 0);
      File(file()).writeAsStringSync('{"anthropic/m": {"calls": "x"}, "odd": 3}');
      expect(UsageMeter(file()).device.calls, 0);
    });
  });
}
