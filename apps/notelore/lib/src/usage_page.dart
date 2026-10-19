import 'package:flutter/material.dart';
import 'package:notelore_core/notelore_core.dart';

import 'session.dart';
import 'strings.dart';
import 'theme.dart';

/// What the model used, for advanced users (#294, #481): a range, the tokens
/// of each day stacked by model, each model's share and cost, and what the
/// messages came to. Cost is an estimate, said so; a provider that reports
/// nothing shows "not available".
class UsagePage extends StatefulWidget {
  const UsagePage(this.session, {super.key});

  final Session session;

  @override
  State<UsagePage> createState() => _UsagePageState();
}

/// Okabe-Ito: told apart with every kind of colour blindness. Dark cards get
/// the lighter blue first, for contrast.
const _light = [
  Color(0xFF0072B2),
  Color(0xFFE69F00),
  Color(0xFF009E73),
  Color(0xFFCC79A7),
  Color(0xFF56B4E9),
  Color(0xFFD55E00),
];
const _dark = [
  Color(0xFF56B4E9),
  Color(0xFFE69F00),
  Color(0xFF009E73),
  Color(0xFFCC79A7),
  Color(0xFFF0E442),
  Color(0xFFD55E00),
];

int _used(UsageCount count) => count.input + count.output;

class _UsagePageState extends State<UsagePage> {
  var _range = UsageRange.twoWeeks;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final s = session.strings;
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final usage = session.usage;
    final tokens = usage.tokensIn(_range);
    final turns = usage.turnsIn(_range).values.fold(const TurnCount(), (a, b) => a + b);
    final days = usage.daysByModel(_range);
    // A model keeps its colour whatever the range: its all-time rank picks it.
    final palette = theme.brightness == Brightness.dark ? _dark : _light;
    final ranked = usage.byModel.entries.toList()
      ..sort((a, b) => _used(b.value.count).compareTo(_used(a.value.count)));
    // shortcut: a seventh model reuses a colour; its name still tells it apart.
    final colors = {for (final (i, e) in ranked.indexed) e.key: palette[i % palette.length]};
    final models = tokens.keys.toList()
      ..sort((a, b) => _used(tokens[b]!).compareTo(_used(tokens[a]!)));
    final total = summarize(tokens);
    String name(String key) => _modelName(s, key);
    Widget lines(UsageSummary summary) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final line in s.usageLines(summary)) Text(line)],
    );
    return Scaffold(
      appBar: AppBar(title: Text(s.usage)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.m, Gap.l),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Layout.column),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Gap.m,
                children: [
                  SegmentedButton<UsageRange>(
                    segments: [
                      for (final range in UsageRange.values)
                        ButtonSegment(value: range, label: Text(s.rangeDays(range.days))),
                    ],
                    selected: {_range},
                    showSelectedIcon: false,
                    onSelectionChanged: (picked) => setState(() => _range = picked.single),
                  ),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          title: Text(s.usageConversation),
                          subtitle: lines(usage.conversation),
                        ),
                        ListTile(title: Text(s.lastDays(_range.days)), subtitle: lines(total)),
                      ],
                    ),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Gap.m),
                      child: _DayBars(days, colors: colors, strings: s, name: name),
                    ),
                  ),
                  if (models.isNotEmpty)
                    _Shares(tokens, models: models, colors: colors, strings: s, name: name),
                  if (turns.turns > 0)
                    _Messages(turns, calls: total.calls, used: _used(total.count), strings: s),
                  if (_range.days == null) Text(s.chartKept(days.length), style: small),
                  if (usage.device.plan || session.spec?.name == 'chatgpt')
                    Text(s.usagePlan, style: small),
                  if (session.spec?.name case 'ollama' || 'device')
                    Text(s.usageLocal, style: small),
                  Text(s.usageEstimate(pricesTaken), style: small),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "provider/model" as the provider's name and the model.
  static String _modelName(Strings s, String key) {
    final cut = key.indexOf('/');
    final provider = providerSpecs.where((p) => p.name == key.substring(0, cut)).firstOrNull;
    final name = provider == null ? key.substring(0, cut) : s.providerName(provider);
    return '$name · ${key.substring(cut + 1)}';
  }
}

/// A small square in a model's colour, beside its name.
class _Swatch extends StatelessWidget {
  const _Swatch(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
  );
}

/// The days of the range as bars, each stacked by model, today on the right.
/// A tap or a drag on the chart names each model's part of that day; a
/// screen reader gets one sentence instead of the bars.
class _DayBars extends StatefulWidget {
  const _DayBars(this.days, {required this.colors, required this.strings, required this.name});

  final List<({DateTime day, Map<String, UsageCount> byModel})> days;
  final Map<String, Color> colors;
  final Strings strings;
  final String Function(String key) name;

  @override
  State<_DayBars> createState() => _DayBarsState();
}

class _DayBarsState extends State<_DayBars> {
  DateTime? _picked;

  static int _dayUsed(Map<String, UsageCount> byModel) =>
      byModel.values.fold(0, (sum, count) => sum + _used(count));

  void _pick(Offset at, double width) {
    final i = (at.dx / width * widget.days.length).floor().clamp(0, widget.days.length - 1);
    setState(() => _picked = widget.days[i].day);
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final days = widget.days;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final small = theme.textTheme.labelSmall;
    final quiet = theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant);
    final total = days.fold(0, (sum, d) => sum + _dayUsed(d.byModel));
    final busiest = days.reduce((a, b) => _dayUsed(b.byModel) > _dayUsed(a.byModel) ? b : a);
    final most = _dayUsed(busiest.byModel);
    final picked = days.where((d) => d.day == _picked).firstOrNull;
    // Fourteen day numbers fit a phone; a longer range names only its first day and today.
    final labelled = days.length <= 14;
    final today = small?.copyWith(color: colors.primary, fontWeight: FontWeight.w700);
    final date = MaterialLocalizations.of(context).formatShortMonthDay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Gap.m,
      children: [
        Row(
          children: [
            Expanded(child: Text(strings.perDay, style: theme.textTheme.titleMedium)),
            Text(strings.number(total), style: theme.textTheme.titleMedium),
          ],
        ),
        Semantics(
          label: total == 0
              ? strings.lastDaysNothing(days.length)
              : strings.lastDaysSummary(days.length, strings.number(total)),
          excludeSemantics: true,
          child: Column(
            spacing: Gap.xs,
            children: [
              LayoutBuilder(
                builder: (context, constraints) => GestureDetector(
                  key: const Key('usage-chart'),
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _pick(d.localPosition, constraints.maxWidth),
                  onHorizontalDragUpdate: (d) => _pick(d.localPosition, constraints.maxWidth),
                  child: SizedBox(
                    height: 136,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      spacing: days.length > 14 ? 1 : Gap.xs,
                      children: [
                        for (final (i, d) in days.indexed)
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              spacing: Gap.xs,
                              children: [
                                Flexible(
                                  child: FractionallySizedBox(
                                    widthFactor: 1,
                                    heightFactor: most == 0 ? 0 : _dayUsed(d.byModel) / most,
                                    child: _Stack(
                                      d.byModel,
                                      colors: widget.colors,
                                      outline: d.day == _picked ? colors.onSurface : null,
                                    ),
                                  ),
                                ),
                                // Never wraps on a narrow phone or with large text.
                                if (labelled)
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      '${d.day.day}',
                                      maxLines: 1,
                                      softWrap: false,
                                      style: i == days.length - 1 ? today : small,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (!labelled)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(date(days.first.day), style: small),
                    Text(date(days.last.day), style: today),
                  ],
                ),
            ],
          ),
        ),
        if (picked != null)
          _Split(
            picked.byModel,
            title: date(picked.day),
            colors: widget.colors,
            strings: strings,
            name: widget.name,
          )
        else if (total > 0) ...[
          Text(strings.busiestDay(strings.number(most), busiest.day.day), style: quiet),
          Text(strings.tapDay, style: quiet),
        ],
      ],
    );
  }
}

/// One day's bar: each model's part, the most used at the bottom, a hairline
/// between parts so neighbours never run together.
class _Stack extends StatelessWidget {
  const _Stack(this.byModel, {required this.colors, this.outline});

  final Map<String, UsageCount> byModel;
  final Map<String, Color> colors;
  final Color? outline;

  @override
  Widget build(BuildContext context) {
    final parts = byModel.entries.where((e) => _used(e.value) > 0).toList()
      ..sort((a, b) => _used(a.value).compareTo(_used(b.value)));
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        border: outline == null ? null : Border.all(color: outline!, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 1,
        children: [
          for (final e in parts)
            Expanded(
              flex: _used(e.value),
              child: ColoredBox(color: colors[e.key]!),
            ),
        ],
      ),
    );
  }
}

/// What each model used on the picked day, in words.
class _Split extends StatelessWidget {
  const _Split(
    this.byModel, {
    required this.title,
    required this.colors,
    required this.strings,
    required this.name,
  });

  final Map<String, UsageCount> byModel;
  final String title;
  final Map<String, Color> colors;
  final Strings strings;
  final String Function(String key) name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = byModel.entries.toList()
      ..sort((a, b) => _used(b.value).compareTo(_used(a.value)));
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Gap.xs,
        children: [
          Text(title, style: theme.textTheme.labelLarge),
          if (parts.isEmpty) Text(strings.usageNothing, style: theme.textTheme.bodySmall),
          for (final e in parts)
            Row(
              spacing: Gap.s,
              children: [
                _Swatch(colors[e.key]!),
                Expanded(child: Text(name(e.key), style: theme.textTheme.bodySmall)),
                Text(strings.number(_used(e.value)), style: theme.textTheme.bodyMedium),
              ],
            ),
        ],
      ),
    );
  }
}

/// Each model's share of the range's tokens: one bar of the whole, then each
/// model with its percent, its tokens and its cost.
class _Shares extends StatelessWidget {
  const _Shares(
    this.tokens, {
    required this.models,
    required this.colors,
    required this.strings,
    required this.name,
  });

  final Map<String, UsageCount> tokens;
  final List<String> models;
  final Map<String, Color> colors;
  final Strings strings;
  final String Function(String key) name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = tokens.values.fold(0, (sum, count) => sum + _used(count));
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Gap.s,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.m),
              child: Text(strings.byModel, style: theme.textTheme.titleMedium),
            ),
            if (all > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.m),
                child: ExcludeSemantics(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 12,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 1,
                        children: [
                          for (final key in models)
                            if (_used(tokens[key]!) > 0)
                              Expanded(
                                flex: _used(tokens[key]!),
                                child: ColoredBox(color: colors[key]!),
                              ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            for (final key in models)
              ListTile(
                leading: _Swatch(colors[key]!),
                minLeadingWidth: 12,
                title: Text(name(key)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in strings.usageLines(summarize({key: tokens[key]!})))
                      Text(line),
                  ],
                ),
                trailing: Text(
                  strings.percent(all == 0 ? 0 : _used(tokens[key]!) / all),
                  style: theme.textTheme.titleMedium,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// What the range's messages came to: the count beside the title, then each
/// figure with its label on the left and the value, larger, on the right.
class _Messages extends StatelessWidget {
  const _Messages(this.turns, {required this.calls, required this.used, required this.strings});

  final TurnCount turns;
  final int calls;
  final int used;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = strings;
    final label = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final value = theme.textTheme.titleMedium;
    final stats = [
      (s.callsPerMessage, s.decimal(calls / turns.turns)),
      (s.tokensPerMessage, s.number((used / turns.turns).round())),
      (s.averageAnswer, s.seconds(s.decimal(turns.averageAnswer.inMilliseconds / 1000))),
      (s.toolCalls, s.number(turns.toolCalls)),
      (s.messagesWrote, s.number(turns.wrote)),
      (s.messagesFailed, s.percent(turns.errorShare)),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Gap.s,
          children: [
            Row(
              key: Key('stat-${s.messages}'),
              children: [
                Expanded(child: Text(s.messages, style: theme.textTheme.titleMedium)),
                Text(s.number(turns.turns), style: value),
              ],
            ),
            for (final (name, figure) in stats)
              Row(
                key: Key('stat-$name'),
                spacing: Gap.s,
                children: [
                  Expanded(child: Text(name, style: label)),
                  Text(figure, style: value),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
