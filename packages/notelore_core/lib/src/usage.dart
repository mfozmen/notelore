/// What the model calls used (#217): tokens per conversation and on this
/// device, and what they cost as an estimate.
///
/// Counts come only from what a provider reported ([TokenUsage]); a call
/// without usage is counted apart, never guessed. Cost is tokens times the
/// list prices in [prices]: an estimate, since providers bill by their own
/// rules (cache rates, long-prompt tiers, Anthropic's web searches). The
/// ChatGPT plan and a local model have no per-token charge.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'providers/base.dart';
import 'store/format.dart' show isoDate;
import 'store/notes.dart' show atomicWrite;

/// US dollars per million tokens.
final class Price {
  const Price(this.input, this.output);

  final double input;
  final double output;
}

/// The day [prices] were taken from the providers' price pages.
const pricesTaken = '2026-10-21';

/// List prices of the models people are likely to pick; any other model has
/// no cost estimate.
const prices = {
  'claude-opus-5-5': Price(4, 20),
  'claude-sonnet-5-5': Price(2, 10),
  'claude-haiku-5-5': Price(0.10, 0.50),
  'claude-opus-4-8': Price(5, 25),
  'claude-sonnet-4-6': Price(3, 15),
  'claude-haiku-4-5': Price(1, 5),
  'gpt-4o': Price(2.50, 10),
  'gpt-4o-mini': Price(0.15, 0.60),
  'gpt-4.1': Price(2, 8),
  'gpt-4.1-mini': Price(0.40, 1.60),
  'gemini-2.5-pro': Price(1.25, 10),
  'gemini-2.5-flash': Price(0.30, 2.50),
  'gemini-2.5-flash-lite': Price(0.10, 0.40),
  'deepseek-flash': Price(0.15, 0.60),
};

/// Providers whose use has no per-token charge.
const _free = {'chatgpt', 'ollama', 'device'};

final class UsageCount {
  const UsageCount({this.calls = 0, this.unreported = 0, this.input = 0, this.output = 0});

  /// Model calls, [unreported] of them without token counts.
  final int calls;
  final int unreported;
  final int input;
  final int output;

  UsageCount add(TokenUsage? usage) =>
      this +
      switch (usage) {
        null => const UsageCount(calls: 1, unreported: 1),
        TokenUsage(:final input, :final output) => UsageCount(
          calls: 1,
          input: input,
          output: output,
        ),
      };

  UsageCount operator +(UsageCount other) => UsageCount(
    calls: calls + other.calls,
    unreported: unreported + other.unreported,
    input: input + other.input,
    output: output + other.output,
  );

  Map<String, int> toJson() => {
    'calls': calls,
    'unreported': unreported,
    'input': input,
    'output': output,
  };
}

/// What the chat turns with one model came to (#481): counts only, never a
/// word of what was said.
final class TurnCount {
  const TurnCount({
    this.turns = 0,
    this.failed = 0,
    this.toolCalls = 0,
    this.wrote = 0,
    this.millis = 0,
  });

  /// Messages answered or failed, [failed] of them with an error.
  final int turns;
  final int failed;
  final int toolCalls;

  /// Turns that wrote notes.
  final int wrote;

  /// Answer time, all turns together.
  final int millis;

  TurnCount add({
    required Duration took,
    required int toolCalls,
    required bool wrote,
    required bool failed,
  }) =>
      this +
      TurnCount(
        turns: 1,
        failed: failed ? 1 : 0,
        toolCalls: toolCalls,
        wrote: wrote ? 1 : 0,
        millis: took.inMilliseconds,
      );

  TurnCount operator +(TurnCount other) => TurnCount(
    turns: turns + other.turns,
    failed: failed + other.failed,
    toolCalls: toolCalls + other.toolCalls,
    wrote: wrote + other.wrote,
    millis: millis + other.millis,
  );

  Duration get averageAnswer =>
      turns == 0 ? Duration.zero : Duration(milliseconds: millis ~/ turns);

  double get toolCallsPerTurn => turns == 0 ? 0 : toolCalls / turns;

  double get errorShare => turns == 0 ? 0 : failed / turns;

  Map<String, int> toJson() => {
    'turns': turns,
    'failed': failed,
    'toolCalls': toolCalls,
    'wrote': wrote,
    'millis': millis,
  };

  /// A damaged count is none.
  static TurnCount fromJson(Map<Object?, Object?> json) {
    try {
      return TurnCount(
        turns: json['turns']! as int,
        failed: json['failed']! as int,
        toolCalls: json['toolCalls']! as int,
        wrote: json['wrote']! as int,
        millis: json['millis']! as int,
      );
    } on Object {
      return const TurnCount();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is TurnCount &&
      other.turns == turns &&
      other.failed == failed &&
      other.toolCalls == toolCalls &&
      other.wrote == wrote &&
      other.millis == millis;

  @override
  int get hashCode => Object.hash(turns, failed, toolCalls, wrote, millis);
}

/// The usage page's ranges (#481): the last [days], or all the device kept.
enum UsageRange {
  week(7),
  twoWeeks(14),
  month(30),
  all(null);

  const UsageRange(this.days);

  final int? days;
}

/// Counts added up over provider and model, for the user to see.
final class UsageSummary {
  const UsageSummary(this.count, {required this.cost, required this.plan, this.billed = true});

  final UsageCount count;
  int get calls => count.calls;
  int get unreported => count.unreported;
  int get input => count.input;
  int get output => count.output;

  /// At least one call reported its tokens.
  bool get tokensKnown => count.calls > count.unreported;

  /// The estimated cost in US dollars; null when a model has no price in the
  /// table or a call did not report its tokens.
  final double? cost;

  /// Some of it ran on the ChatGPT plan: no per-token charge.
  final bool plan;

  /// Some of it ran where tokens are charged; without that, there is no cost
  /// to state, only where it went (#436).
  final bool billed;
}

/// [counts] ("provider/model" to count) as one summary.
UsageSummary summarize(Map<String, UsageCount> counts) {
  double? cost = 0;
  var billed = false;
  for (final MapEntry(:key, value: count) in counts.entries) {
    final cut = key.indexOf('/');
    final (provider, model) = (key.substring(0, cut), key.substring(cut + 1));
    if (_free.contains(provider)) continue;
    billed = true;
    final price = prices[model];
    if (price == null || count.unreported > 0) {
      cost = null;
      break;
    }
    cost = cost! + (count.input * price.input + count.output * price.output) / 1e6;
  }
  return UsageSummary(
    counts.values.fold(const UsageCount(), (total, count) => total + count),
    cost: cost,
    plan: counts.keys.any((key) => key.startsWith('chatgpt/')),
    billed: billed,
  );
}

/// The counts of this conversation, in memory, and of this device, kept in
/// [file], with each day's apart in `usage-days.json` beside it for the last
/// days chart (#294); derived state: deleting either only resets it.
class UsageMeter {
  UsageMeter(this.file, {DateTime Function()? today}) : _today = today ?? DateTime.now;

  final String file;
  final DateTime Function() _today;
  final _conversation = <String, UsageCount>{};
  late final _device = _counts(_read(file));
  late final _days = _loadDays();
  late final _turns = _loadTurns();

  String get _daysFile => p.join(p.dirname(file), 'usage-days.json');

  /// The turns, `{total: {model: count}, days: {date: {model: count}}}`.
  String get _turnsFile => p.join(p.dirname(file), 'usage-turns.json');

  /// Days kept; older ones are dropped on the next record.
  static const _keep = 90;

  UsageSummary get conversation => summarize(_conversation);
  UsageSummary get device => summarize(_device);

  /// Each "provider/model" used on this device, on its own.
  Map<String, UsageSummary> get byModel => {
    for (final MapEntry(:key, :value) in _device.entries) key: summarize({key: value}),
  };

  /// The last [n] local calendar days, oldest first, each its total (zero
  /// when nothing was used).
  List<({DateTime day, UsageCount count})> lastDays(int n) {
    final now = _today();
    final today = DateTime(now.year, now.month, now.day);
    return [
      for (var i = n - 1; i >= 0; i--)
        () {
          final day = DateTime(today.year, today.month, today.day - i);
          final counts = _days[isoDate(day)]?.values ?? const <UsageCount>[];
          return (day: day, count: counts.fold(const UsageCount(), (a, b) => a + b));
        }(),
    ];
  }

  void record(String provider, String model, TokenUsage? usage) {
    final key = '$provider/$model';
    _conversation[key] = (_conversation[key] ?? const UsageCount()).add(usage);
    _device[key] = (_device[key] ?? const UsageCount()).add(usage);
    final day = _days.putIfAbsent(isoDate(_today()), () => {});
    day[key] = (day[key] ?? const UsageCount()).add(usage);
    final oldest = isoDate(_today().subtract(const Duration(days: _keep)));
    _days.removeWhere((date, _) => date.compareTo(oldest) < 0);
    _save(file, _device);
    _save(_daysFile, _days);
  }

  /// One chat turn with [provider]'s [model] (#481), on today's date.
  void recordTurn(
    String provider,
    String model, {
    required Duration took,
    required int toolCalls,
    required bool wrote,
    required bool failed,
  }) {
    final key = '$provider/$model';
    TurnCount added(TurnCount? count) => (count ?? const TurnCount()).add(
      took: took,
      toolCalls: toolCalls,
      wrote: wrote,
      failed: failed,
    );
    _turns.total[key] = added(_turns.total[key]);
    final day = _turns.days.putIfAbsent(isoDate(_today()), () => {});
    day[key] = added(day[key]);
    final oldest = isoDate(_today().subtract(const Duration(days: _keep)));
    _turns.days.removeWhere((date, _) => date.compareTo(oldest) < 0);
    _save(_turnsFile, {'total': _turns.total, 'days': _turns.days});
  }

  /// The last [n] local dates, newest last.
  List<DateTime> _dates(int n) {
    final now = _today();
    return [for (var i = n - 1; i >= 0; i--) DateTime(now.year, now.month, now.day - i)];
  }

  static Map<String, T> _sum<T>(Iterable<Map<String, T>> maps, T Function(T, T) plus) {
    final sum = <String, T>{};
    for (final map in maps) {
      for (final MapEntry(:key, :value) in map.entries) {
        sum[key] = sum.containsKey(key) ? plus(sum[key] as T, value) : value;
      }
    }
    return sum;
  }

  /// Tokens per "provider/model" in [range].
  Map<String, UsageCount> tokensIn(UsageRange range) => switch (range.days) {
    null => Map.of(_device),
    final n => _sum([for (final d in _dates(n)) ?_days[isoDate(d)]], (a, b) => a + b),
  };

  /// Turns per "provider/model" in [range].
  Map<String, TurnCount> turnsIn(UsageRange range) => switch (range.days) {
    null => Map.of(_turns.total),
    final n => _sum([for (final d in _dates(n)) ?_turns.days[isoDate(d)]], (a, b) => a + b),
  };

  /// Each day of [range], oldest first, its tokens per model apart: the
  /// chart's bars. All time charts the days kept.
  List<({DateTime day, Map<String, UsageCount> byModel})> daysByModel(UsageRange range) => [
    for (final day in _dates(range.days ?? _keep))
      (day: day, byModel: Map.of(_days[isoDate(day)] ?? const {})),
  ];

  void newConversation() => _conversation.clear();

  /// Bookkeeping never fails an answer: the next call saves it again.
  static void _save(String path, Object value) {
    try {
      File(path).parent.createSync(recursive: true);
      atomicWrite(path, '${jsonEncode(value)}\n');
    } on FileSystemException {
      // not saved this time
    }
  }

  Map<String, Map<String, UsageCount>> _loadDays() {
    final days = <String, Map<String, UsageCount>>{};
    for (final MapEntry(:key, :value) in _read(_daysFile).entries) {
      if ((key, value) case (final String date, final Map<Object?, Object?> day)) {
        days[date] = _counts(day);
      }
    }
    return days;
  }

  ({Map<String, TurnCount> total, Map<String, Map<String, TurnCount>> days}) _loadTurns() {
    Map<String, TurnCount> counts(Object? saved) => {
      if (saved is Map)
        for (final MapEntry(:key, :value) in saved.entries)
          if (value is Map) '$key': TurnCount.fromJson(value),
    };
    final saved = _read(_turnsFile);
    final days = saved['days'];
    return (
      total: counts(saved['total']),
      days: {
        if (days is Map)
          for (final MapEntry(:key, :value) in days.entries) '$key': counts(value),
      },
    );
  }

  static Map<Object?, Object?> _read(String path) {
    try {
      return jsonDecode(File(path).readAsStringSync()) as Map;
    } on Object {
      return {}; // none yet, or damaged: it starts again
    }
  }

  static Map<String, UsageCount> _counts(Map<Object?, Object?> saved) {
    try {
      return {
        for (final MapEntry(:key, :value) in saved.cast<String, Map<String, Object?>>().entries)
          key: UsageCount(
            calls: value['calls']! as int,
            unreported: value['unreported']! as int,
            input: value['input']! as int,
            output: value['output']! as int,
          ),
      };
    } on Object {
      return {}; // damaged: the total starts again
    }
  }
}

/// [provider] with every call's usage recorded in [meter] under [name].
class MeteredProvider implements LlmProvider {
  MeteredProvider(this.provider, this.name, this.meter);

  final LlmProvider provider;
  final String name;
  final UsageMeter meter;

  @override
  String get model => provider.model;

  @override
  Future<AgentResponse> turn(String system, List<Message> messages, List<Tool> tools) async {
    final response = await provider.turn(system, messages, tools);
    meter.record(name, provider.model, response.usage);
    return response;
  }
}
