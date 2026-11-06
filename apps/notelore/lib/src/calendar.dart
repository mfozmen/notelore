import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;

import 'app.dart' show AppMenu;
import 'empty_state.dart';
import 'note_view.dart';
import 'section_label.dart';
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
              child: WritableNoteView(
                session,
                note,
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

  Future<void> _complete(DayItem item) => widget.session.setTodoDone(
    NoteInfo(item.slug, item.kind, item.note, null),
    item.number,
    text: item.text,
    done: true,
  );

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
    if (items.isEmpty) {
      return EmptyState(
        icon: Icons.event_available,
        title: s.nothingPlanned,
        hint: s.calendarExample,
        actions: [FilledButton.tonal(onPressed: widget.toChat, child: Text(s.goToChat))],
      );
    }
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
      toggle: _complete,
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
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.m, Gap.m),
                children: [grid],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              // Beside the grid, not floating off on a very wide window.
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: Layout.column),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(Gap.m, 0, Gap.m, Gap.m),
                    children: [list],
                  ),
                ),
              ),
            ),
          ],
        )
      : ListView(
          padding: const EdgeInsets.fromLTRB(Gap.m, 0, Gap.m, Gap.l),
          children: [grid, list],
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
    final mono = theme.extension<NoteloreTokens>()!.label;
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: s.previousMonth,
              color: colors.onSurfaceVariant,
              icon: const Icon(Icons.chevron_left),
              onPressed: () => turn(-1),
            ),
            Expanded(
              // Smaller, never cut, beside the chip and arrows at large text.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  s.monthYear(month),
                  maxLines: 1,
                  style: theme.textTheme.titleMedium?.copyWith(fontSize: 19),
                ),
              ),
            ),
            Tooltip(
              message: s.today,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: colors.surfaceContainerLow,
                  shape: StadiumBorder(side: BorderSide(color: colors.outlineVariant)),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  // A 48 dp target around the small chip.
                  minimumSize: const Size(48, 32),
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                onPressed: todayTap,
                child: Text(
                  s.caps(s.today),
                  semanticsLabel: s.today,
                  style: mono.copyWith(fontSize: 10, letterSpacing: 1.2),
                ),
              ),
            ),
            IconButton(
              tooltip: s.nextMonth,
              color: colors.onSurfaceVariant,
              icon: const Icon(Icons.chevron_right),
              onPressed: () => turn(1),
            ),
          ],
        ),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: colors.outlineVariant),
          ),
          child: Padding(
            // Narrow sides, so a day keeps as much of its 48 dp width as fits.
            padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.s, Gap.xs, Gap.xs),
            child: Column(
              children: [
                Row(
                  children: [
                    for (final day in s.weekdays)
                      Expanded(
                        child: ExcludeSemantics(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                            child: Text(
                              s.caps(day),
                              textAlign: TextAlign.center,
                              style: mono.copyWith(
                                fontSize: 9.5,
                                letterSpacing: 1,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                _days(colors, lead, days),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _days(ColorScheme colors, int lead, int days) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
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
  );
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
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: chosen ? colors.primary : null,
              border: today && !chosen ? Border.all(color: colors.primary, width: 1.5) : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.translate(
                  // Lifts the number above the dot so the pair reads centered.
                  offset: const Offset(0, -2),
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.5,
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: chosen ? colors.onPrimary : colors.onSurface,
                        fontWeight: today || chosen ? FontWeight.w700 : null,
                      ),
                    ),
                  ),
                ),
                if (marked)
                  Positioned(
                    bottom: 3,
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: chosen ? colors.onPrimary : (dot ?? colors.primary),
                      ),
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
    required this.showAll,
    required this.open,
    required this.toggle,
  });

  final Strings s;
  final List<DayItem> items;
  final DateTime today;
  final DateTime? picked;
  final VoidCallback showAll;
  final ValueChanged<DayItem> open;
  final ValueChanged<DayItem> toggle;

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
          if (picked == null) SectionLabel(name.$1, strings: s, late: name.$2),
          Card(
            margin: const EdgeInsets.only(bottom: Gap.s),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (index, item) in group.indexed) ...[
                  if (index > 0) const Divider(),
                  _Item(
                    s,
                    item,
                    today: today,
                    open: open,
                    toggle: toggle,
                    underOverdue: picked == null,
                  ),
                ],
              ],
            ),
          ),
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
    required this.toggle,
    required this.underOverdue,
  });

  final Strings s;
  final DayItem item;
  final DateTime today;
  final ValueChanged<DayItem> open;
  final ValueChanged<DayItem> toggle;

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
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.only(left: Gap.xs, right: Gap.m),
      minTileHeight: 56,
      horizontalTitleGap: Gap.xs,
      leading: SizedBox(
        width: 48,
        child: Center(
          child: item.todo
              ? Checkbox(
                  value: false,
                  side: BorderSide(color: late ? colors.error : colors.primary, width: 2),
                  onChanged: (_) => toggle(item),
                )
              : Icon(Icons.alarm, size: 20, color: late ? colors.error : colors.primary),
        ),
      ),
      title: Text(
        item.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: Text(
        when,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
      ),
      onTap: () => open(item),
    );
  }
}
