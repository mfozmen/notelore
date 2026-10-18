import 'package:flutter/material.dart';
import 'package:notelore_core/notelore_core.dart';

import 'session.dart';
import 'strings.dart';
import 'theme.dart';

/// What the model used, for advanced users (#294): this conversation and this
/// device, the last two weeks as bars, and each model on its own. Cost is an
/// estimate, said so; a provider that reports nothing shows "not available".
class UsagePage extends StatelessWidget {
  const UsagePage(this.session, {super.key});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final usage = session.usage;
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
                  Card(
                    child: Column(
                      children: [
                        for (final (title, summary) in [
                          (s.usageConversation, usage.conversation),
                          (s.usageDevice, usage.device),
                        ])
                          ListTile(title: Text(title), subtitle: lines(summary)),
                      ],
                    ),
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(Gap.m),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: Gap.m,
                        children: [_DayBars(usage.lastDays(14), strings: s)],
                      ),
                    ),
                  ),
                  if (usage.byModel.isNotEmpty)
                    Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(Gap.m, Gap.m, Gap.m, 0),
                            child: Text(s.byModel, style: theme.textTheme.titleMedium),
                          ),
                          for (final MapEntry(:key, value: summary) in usage.byModel.entries)
                            ListTile(title: Text(_modelName(s, key)), subtitle: lines(summary)),
                        ],
                      ),
                    ),
                  if (usage.device.plan || session.spec?.name == 'chatgpt')
                    Text(s.usagePlan, style: small),
                  if (session.spec?.name == 'ollama') Text(s.usageLocal, style: small),
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

/// The last days as bars, tallest the busiest, today on the right. One
/// sentence for a screen reader instead of fourteen bars.
class _DayBars extends StatelessWidget {
  const _DayBars(this.days, {required this.strings});

  final List<({DateTime day, UsageCount count})> days;
  final Strings strings;

  static int _used(UsageCount count) => count.input + count.output;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final small = theme.textTheme.labelSmall;
    final total = days.fold(0, (sum, d) => sum + _used(d.count));
    final busiest = days.reduce((a, b) => _used(b.count) > _used(a.count) ? b : a);
    final most = _used(busiest.count);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Gap.m,
      children: [
        // The amount in sight, not only the shape (#294).
        Row(
          children: [
            Expanded(child: Text(strings.lastDays, style: theme.textTheme.titleMedium)),
            Text(strings.number(total), style: theme.textTheme.titleMedium),
          ],
        ),
        Semantics(
          label: total == 0
              ? strings.lastDaysNothing
              : strings.lastDaysSummary(strings.number(total)),
          excludeSemantics: true,
          child: SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: Gap.xs,
              children: [
                for (final (i, d) in days.indexed)
                  Expanded(
                    child: Tooltip(
                      message: strings.number(_used(d.count)),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        spacing: Gap.xs,
                        children: [
                          Flexible(
                            child: FractionallySizedBox(
                              heightFactor: most == 0 ? 0 : _used(d.count) / most,
                              child: Container(
                                decoration: BoxDecoration(
                                  // 3:1 or more on the card in both themes; today stands out.
                                  color: i == days.length - 1 ? colors.primary : colors.outline,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Never wraps on a narrow phone or with large text.
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '${d.day.day}',
                              maxLines: 1,
                              softWrap: false,
                              style: i == days.length - 1
                                  ? small?.copyWith(
                                      color: colors.primary,
                                      fontWeight: FontWeight.w700,
                                    )
                                  : small,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (total > 0)
          Text(
            strings.busiestDay(strings.number(most), busiest.day.day),
            style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
      ],
    );
  }
}
