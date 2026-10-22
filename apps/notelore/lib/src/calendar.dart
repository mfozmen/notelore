import 'dart:io';

import 'package:flutter/material.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;

import 'app.dart' show AppMenu;
import 'note_view.dart';
import 'session.dart';
import 'strings.dart';
import 'theme.dart';

/// The notes' own calendar (#453): every reminder and dated open todo, read
/// from the notes, on a month grid with the chosen day's list beside it or
/// below. Nothing is chosen: what is coming, the late todos first.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen(this.session, {required this.toChat, super.key});

  final Session session;

  /// Goes to the chat, where reminders are made.
  final VoidCallback toChat;

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
    final String text;
    try {
      text = session.readNote(note);
    } on FileSystemException {
      setState(() {}); // archived or moved since the list was drawn
      return;
    }
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
      return Scaffold(
        appBar: AppBar(leading: AppMenu.button(context), title: Text(s.calendar)),
        body: LayoutBuilder(
          builder: (context, box) => _layout(
            wide: box.maxWidth >= Layout.wide,
            grid: _grid(s, items, today),
            list: _list(s, items, today),
          ),
        ),
      );
    },
  );

  Widget _grid(Strings s, List<DayItem> items, DateTime today) => _MonthGrid(
    s,
    month: _month,
    today: today,
    picked: _picked,
    marked: {for (final item in items) item.day},
    late: {
      for (final item in items)
        if (item.todo && item.day.isBefore(today)) item.day,
    },
    pick: (day) => setState(() => _picked = day == _picked ? null : day),
    turn: (by) => setState(() => _month = DateTime(_month.year, _month.month + by)),
    todayTap: () => setState(() {
      _month = _monthOf(today);
      _picked = null;
    }),
  );

  Widget _list(Strings s, List<DayItem> items, DateTime today) {
    if (items.isEmpty) return _Empty(s, toChat: widget.toChat);
    return _Agenda(
      s,
      items: [
        for (final i in items)
          if (_picked == null || i.day == _picked) i,
      ],
      today: today,
      picked: _picked,
      showAll: () => setState(() => _picked = null),
      open: _open,
    );
  }

  /// Side by side on a wide window, the list beside the grid; one below the
  /// other on a phone.
  Widget _layout({required bool wide, required Widget grid, required Widget list}) => wide
      ? Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 380,
              child: ListView(padding: const EdgeInsets.all(Gap.m), children: [grid]),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              // Beside the grid, not floating off on a very wide window.
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: Layout.column),
                  child: ListView(padding: const EdgeInsets.all(Gap.m), children: [list]),
                ),
              ),
            ),
          ],
        )
      : ListView(
          padding: const EdgeInsets.fromLTRB(Gap.m, 0, Gap.m, Gap.l),
          children: [
            grid,
            const SizedBox(height: Gap.m),
            list,
          ],
        );
}

/// A month, Monday first, in 48 dp rows: today ringed, the chosen day filled,
/// a dot under each day with something on it (red when all of it is late).
class _MonthGrid extends StatelessWidget {
  const _MonthGrid(
    this.s, {
    required this.month,
    required this.today,
    required this.picked,
    required this.marked,
    required this.late,
    required this.pick,
    required this.turn,
    required this.todayTap,
  });

  final Strings s;
  final DateTime month;
  final DateTime today;
  final DateTime? picked;
  final Set<DateTime> marked;
  final Set<DateTime> late;
  final ValueChanged<DateTime> pick;
  final ValueChanged<int> turn;
  final VoidCallback todayTap;

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
            Tooltip(
              message: s.today,
              child: TextButton(onPressed: todayTap, child: Text(s.today)),
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
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // Rows of 48 dp, not square cells: the list below stays in sight.
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 48,
          ),
          itemCount: lead + days,
          itemBuilder: (context, i) {
            if (i < lead) return const SizedBox.shrink();
            final day = DateTime(month.year, month.month, i - lead + 1);
            return _Day(
              day,
              label: s.dayHeading(day),
              today: day == today,
              chosen: day == picked,
              dot: late.contains(day) ? colors.error : null,
              marked: marked.contains(day),
              pick: pick,
            );
          },
        ),
      ],
    );
  }
}

class _Day extends StatelessWidget {
  const _Day(
    this.day, {
    required this.label,
    required this.today,
    required this.chosen,
    required this.marked,
    required this.dot,
    required this.pick,
  });

  final DateTime day;
  final String label;
  final bool today;
  final bool chosen;
  final bool marked;

  /// The dot's colour when it is not the plain one: red for late todos.
  final Color? dot;
  final ValueChanged<DateTime> pick;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: chosen,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => pick(day),
        child: Center(
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: chosen ? colors.primary : null,
              border: today && !chosen ? Border.all(color: colors.primary, width: 1.5) : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${day.day}',
                  style: TextStyle(
                    color: chosen ? colors.onPrimary : colors.onSurface,
                    fontWeight: today ? FontWeight.w600 : null,
                  ),
                ),
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: !marked
                        ? Colors.transparent
                        : (chosen ? colors.onPrimary : (dot ?? colors.primary)),
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

/// Nothing planned yet: where these come from, and the way to make one.
class _Empty extends StatelessWidget {
  const _Empty(this.s, {required this.toChat});

  final Strings s;
  final VoidCallback toChat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.l),
      child: Column(
        children: [
          Icon(Icons.event_available, size: 48, color: muted),
          const SizedBox(height: Gap.m),
          Text(s.nothingPlanned, textAlign: TextAlign.center),
          const SizedBox(height: Gap.s),
          Text(
            s.calendarExample,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: Gap.m),
          FilledButton.tonal(onPressed: toChat, child: Text(s.goToChat)),
        ],
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
    required this.showAll,
    required this.open,
  });

  final Strings s;
  final List<DayItem> items;
  final DateTime today;
  final DateTime? picked;
  final VoidCallback showAll;
  final ValueChanged<DayItem> open;

  String _heading(DateTime day) {
    if (day == today) return s.today;
    if (day == today.add(const Duration(days: 1))) return s.tomorrow;
    return s.dayHeading(day);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = <(String, bool), List<DayItem>>{};
    for (final item in items) {
      final late = picked == null && item.todo && item.day.isBefore(today);
      groups.putIfAbsent((late ? s.overdueGroup : _heading(item.day), late), () => []).add(item);
    }
    Widget heading((String, bool) group) => Text(
      group.$1,
      style: theme.textTheme.titleSmall?.copyWith(
        color: group.$2 ? theme.colorScheme.error : theme.colorScheme.primary,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (picked case final day?) ...[
          // As tall as the month's row, so nothing moves when a day is picked.
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(child: Text(_heading(day), style: theme.textTheme.titleMedium)),
                TextButton.icon(
                  icon: const Icon(Icons.close),
                  label: Text(s.showAll),
                  onPressed: showAll,
                ),
              ],
            ),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.m),
              child: Text(
                s.nothingThatDay,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
        for (final MapEntry(key: name, value: group) in groups.entries) ...[
          if (picked == null)
            Padding(
              padding: const EdgeInsets.only(top: Gap.m, bottom: Gap.xs),
              child: heading(name),
            ),
          for (final item in group)
            _Item(s, item, today: today, open: open, underOverdue: picked == null),
        ],
      ],
    );
  }
}

class _Item extends StatelessWidget {
  const _Item(
    this.s,
    this.item, {
    required this.today,
    required this.open,
    required this.underOverdue,
  });

  final Strings s;
  final DayItem item;
  final DateTime today;
  final ValueChanged<DayItem> open;

  /// Under an "Overdue" heading already: it need not say so again.
  final bool underOverdue;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final late = item.todo && item.day.isBefore(today);
    final date = s.shortDate(item.day, today);
    final when = [
      ?item.time,
      if (late) underOverdue ? date : s.overdue(date),
      item.note,
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        item.todo ? Icons.radio_button_unchecked : Icons.alarm,
        color: late ? colors.error : colors.primary,
      ),
      title: Text(item.text),
      subtitle: Text(when, style: TextStyle(color: colors.onSurfaceVariant)),
      onTap: () => open(item),
    );
  }
}
