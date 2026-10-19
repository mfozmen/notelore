import 'package:flutter/material.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;

import 'note_view.dart';
import 'session.dart';
import 'strings.dart';
import 'theme.dart';

/// The notes' own calendar (#453): every reminder and dated open todo, read
/// from the notes, on a month grid with the chosen day's list beside it or
/// below. Nothing is chosen: what is coming, the late todos first.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen(this.session, {super.key});

  final Session session;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month = _monthOf(_today);
  DateTime? _picked;

  DateTime get _today {
    final now = widget.session.clock().toLocal();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime _monthOf(DateTime day) => DateTime(day.year, day.month);

  void _open(DayItem item) {
    final session = widget.session;
    final note = NoteInfo(item.slug, item.kind, item.note, null);
    final text = session.readNote(note);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(item.note)),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Layout.column),
              child: NoteView(
                text,
                folder: p.dirname(notePath(session.paths.notes.path, item.kind, item.slug)),
                strings: session.strings,
                today: _today,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      final s = widget.session.strings;
      final today = _today;
      final items = calendarItems(widget.session.paths.notes.path, today: today);
      final grid = _MonthGrid(
        s,
        month: _month,
        today: today,
        picked: _picked,
        marked: {for (final item in items) item.day},
        pick: (day) => setState(() => _picked = day == _picked ? null : day),
        turn: (by) => setState(() => _month = DateTime(_month.year, _month.month + by)),
      );
      final list = _Agenda(
        s,
        items: _picked == null
            ? items
            : [
                for (final i in items)
                  if (i.day == _picked) i,
              ],
        today: today,
        picked: _picked,
        upcoming: () => setState(() => _picked = null),
        open: _open,
      );
      return LayoutBuilder(
        builder: (context, box) => box.maxWidth >= Layout.wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 380,
                    child: ListView(padding: const EdgeInsets.all(Gap.m), children: [grid]),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: Layout.column),
                        child: ListView(padding: const EdgeInsets.all(Gap.m), children: [list]),
                      ),
                    ),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(Gap.m, Gap.m, Gap.m, Gap.l),
                children: [
                  grid,
                  const SizedBox(height: Gap.l),
                  list,
                ],
              ),
      );
    },
  );
}

/// A month, Monday first: today ringed, the chosen day filled, a dot under
/// each day with something on it.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid(
    this.s, {
    required this.month,
    required this.today,
    required this.picked,
    required this.marked,
    required this.pick,
    required this.turn,
  });

  final Strings s;
  final DateTime month;
  final DateTime today;
  final DateTime? picked;
  final Set<DateTime> marked;
  final ValueChanged<DateTime> pick;
  final ValueChanged<int> turn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final lead = DateTime(month.year, month.month).weekday - 1; // Monday is 1
    final days = DateTime(month.year, month.month + 1, 0).day;
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: s.previousMonth,
              icon: const Icon(Icons.chevron_left),
              onPressed: () => turn(-1),
            ),
            Expanded(
              child: Text(
                s.monthYear(month),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: s.nextMonth,
              icon: const Icon(Icons.chevron_right),
              onPressed: () => turn(1),
            ),
          ],
        ),
        const SizedBox(height: Gap.s),
        Row(
          children: [
            for (final day in s.weekdays)
              Expanded(
                child: ExcludeSemantics(
                  child: Text(
                    day,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Gap.xs),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < lead; i++) const SizedBox.shrink(),
            for (var d = 1; d <= days; d++)
              _Day(
                DateTime(month.year, month.month, d),
                today: today,
                picked: picked,
                marked: marked,
                pick: pick,
                label: s.shortDate,
              ),
          ],
        ),
      ],
    );
  }
}

class _Day extends StatelessWidget {
  const _Day(
    this.day, {
    required this.today,
    required this.picked,
    required this.marked,
    required this.pick,
    required this.label,
  });

  final DateTime day;
  final DateTime today;
  final DateTime? picked;
  final Set<DateTime> marked;
  final ValueChanged<DateTime> pick;
  final String Function(DateTime, DateTime) label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final chosen = day == picked;
    final isToday = day == today;
    return Semantics(
      button: true,
      selected: chosen,
      label: label(day, today),
      excludeSemantics: true,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => pick(day),
        child: Center(
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: chosen ? colors.primary : null,
              border: isToday && !chosen ? Border.all(color: colors.primary) : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${day.day}',
                  style: TextStyle(color: chosen ? colors.onPrimary : colors.onSurface),
                ),
                Container(
                  width: 4,
                  height: 4,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: marked.contains(day)
                        ? (chosen ? colors.onPrimary : colors.primary)
                        : Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The chosen day's things, or (none chosen) what is coming: late todos under
/// their own heading, then each day under its date.
class _Agenda extends StatelessWidget {
  const _Agenda(
    this.s, {
    required this.items,
    required this.today,
    required this.picked,
    required this.upcoming,
    required this.open,
  });

  final Strings s;
  final List<DayItem> items;
  final DateTime today;
  final DateTime? picked;
  final VoidCallback upcoming;
  final ValueChanged<DayItem> open;

  String _heading(DateTime day) {
    if (day == today) return s.today;
    if (day == today.add(const Duration(days: 1))) return s.tomorrow;
    return '${s.weekdayName(day)}, ${s.shortDate(day, today)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = <String, List<DayItem>>{};
    for (final item in items) {
      final late = item.todo && item.day.isBefore(today);
      groups.putIfAbsent(late ? s.overdueGroup : _heading(item.day), () => []).add(item);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                picked == null ? s.upcoming : _heading(picked!),
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (picked != null) TextButton(onPressed: upcoming, child: Text(s.upcoming)),
          ],
        ),
        const SizedBox(height: Gap.s),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.m),
            child: Text(
              picked == null ? s.nothingPlanned : s.nothingThatDay,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final MapEntry(key: heading, value: group) in groups.entries) ...[
          if (picked == null)
            Padding(
              padding: const EdgeInsets.only(top: Gap.m, bottom: Gap.xs),
              child: Text(
                heading,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: heading == s.overdueGroup
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
              ),
            ),
          for (final item in group) _Item(s, item, today: today, open: open),
        ],
      ],
    );
  }
}

class _Item extends StatelessWidget {
  const _Item(this.s, this.item, {required this.today, required this.open});

  final Strings s;
  final DayItem item;
  final DateTime today;
  final ValueChanged<DayItem> open;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final late = item.todo && item.day.isBefore(today);
    final when = [
      ?item.time,
      if (late) s.overdue(s.shortDate(item.day, today)),
      item.note,
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        item.todo ? Icons.radio_button_unchecked : Icons.alarm,
        color: late ? colors.error : colors.primary,
      ),
      title: Text(item.text),
      subtitle: Text(when, style: TextStyle(color: late ? colors.error : null)),
      onTap: () => open(item),
    );
  }
}
