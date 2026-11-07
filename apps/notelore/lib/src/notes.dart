import 'dart:async';

import 'package:flutter/material.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;

import 'app.dart' show AppMenu;
import 'empty_state.dart';
import 'note_view.dart';
import 'section_label.dart';
import 'session.dart';
import 'strings.dart';
import 'sync_state.dart';
import 'theme.dart';
import 'transfer.dart';

/// Every project and topic, newest first; a tap opens the note read-only, beside
/// the list on a wide window. The open note's header archives it.
class NotesScreen extends StatefulWidget {
  const NotesScreen(this.session, {required this.toChat, this.open, super.key});

  final Session session;

  /// Open in the reader from the start: the note a chat receipt opened.
  final NoteInfo? open;

  /// Goes to the chat, where notes are made (#721).
  final VoidCallback toChat;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

enum _NotesAction { import, export }

class _NotesScreenState extends State<NotesScreen> {
  /// The note open beside the list on a wide window, read once.
  late (NoteInfo, String)? _reading = switch (widget.open) {
    final note? => (note, widget.session.readNote(note)),
    null => null,
  };

  /// What the list is narrowed to; empty shows every note.
  final _search = TextEditingController();

  /// The archive open in the content pane, on a wide window.
  var _archive = false;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.session.removeListener(_sessionChanged);
    _search.dispose();
    super.dispose();
  }

  bool _isOpen(NoteInfo note) => _reading?.$1.kind == note.kind && _reading?.$1.slug == note.slug;

  /// Asks, then archives [note] with an Undo; true when it was deleted.
  Future<bool> _delete(NoteInfo note) async {
    final s = widget.session.strings;
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(s.deleteQuestion(note.title)),
        content: Text(s.deleteExplained),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(s.cancel)),
          FilledButton(
            // Deleting, so the error colour, not the brand's.
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialog).colorScheme.error,
              foregroundColor: Theme.of(dialog).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return false;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    final archived = await widget.session.deleteNote(note);
    setState(() {
      if (_isOpen(note)) _reading = null;
    });
    if (archived == null) {
      messenger.showSnackBar(SnackBar(content: Text(s.alreadyGone(note.title))));
      return true;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(s.movedToArchive(note.title)),
        // Flutter keeps a snackbar with an action until dismissed: this one goes.
        persist: false,
        duration: const Duration(seconds: 6),
        showCloseIcon: true,
        action: SnackBarAction(
          label: s.undo,
          onPressed: () async {
            await widget.session.restoreNote(note, archived);
            if (mounted) setState(() {});
          },
        ),
      ),
    );
    return true;
  }

  /// Asks for a format, exports [notes] and says how it went (#215).
  Future<void> _export(List<NoteInfo> notes) async {
    final s = widget.session.strings;
    final format = await showDialog<ExportFormat>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: Text(s.exportAs),
        children: [
          for (final format in ExportFormat.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, format),
              child: Text(s.formatName(format)),
            ),
        ],
      ),
    );
    if (format == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    String said;
    try {
      if (!await widget.session.exportNotes(notes, format)) return; // called off
      said = s.exported(notes.length);
    } on Exception catch (error) {
      said = s.exportFailed('$error');
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(said)));
  }

  /// Several notes at once: which ones, then the format.
  Future<void> _exportSeveral(List<NoteInfo> notes) async {
    final chosen = await showDialog<List<NoteInfo>>(
      context: context,
      builder: (_) => _ChooseNotes(notes, widget.session.strings),
    );
    if (chosen != null && mounted) await _export(chosen);
  }

  Future<void> _refresh() async {
    setState(() {});
    // Rereading is instant; without a pause the spinner never shows and a tap looks dead.
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  // One key: only one list (empty or full) is built at a time.
  final _refresher = GlobalKey<RefreshIndicatorState>();

  Widget _refreshable(Widget child) =>
      RefreshIndicator(key: _refresher, onRefresh: _refresh, child: child);

  Widget _listHeader(BuildContext context, List<NoteInfo> notes) => Padding(
    // Gap.xs, not Gap.s: the menu icon sits 12px inside its 48px button, so
    // its edge lands on the field's Gap.m edge below.
    padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.xs, 0),
    child: Align(alignment: Alignment.centerRight, child: _listActions(context, notes)),
  );

  Widget _listActions(BuildContext context, List<NoteInfo> notes) {
    final s = widget.session.strings;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: s.archive,
          icon: const Icon(Icons.inventory_2_outlined),
          onPressed: () => Layout.isWide(context)
              ? setState(() => _archive = true)
              : Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => ArchiveScreen(widget.session))),
        ),
        IconButton(
          tooltip: s.refresh,
          icon: const Icon(Icons.refresh),
          // The pull's spinner shows it, and a tap while it runs is ignored.
          onPressed: () => _refresher.currentState?.show(),
        ),
        PopupMenuButton<_NotesAction>(
          key: const Key('notes-more'),
          tooltip: s.moreNoteActions,
          icon: const Icon(Icons.more_vert),
          onSelected: (action) async {
            switch (action) {
              case _NotesAction.import:
                await _import();
              case _NotesAction.export:
                await _exportSeveral(notes);
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(value: _NotesAction.import, child: Text(s.importNotes)),
            PopupMenuItem(
              value: _NotesAction.export,
              enabled: notes.isNotEmpty,
              child: Text(s.exportNotes),
            ),
          ],
        ),
      ],
    );
  }

  /// Imports the files the person picks and says what happened to each.
  Future<void> _import() async {
    final s = widget.session.strings;
    final messenger = ScaffoldMessenger.of(context);
    final reports = await widget.session.importNotes();
    if (reports.isEmpty || !mounted) return; // called off
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          showCloseIcon: true,
          duration: const Duration(seconds: 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final report in reports) Text(_reported(s, report))],
          ),
        ),
      );
    setState(() {});
  }

  static String _reported(Strings s, ImportReport report) => switch (report.imported) {
    null => s.importRefused(report.file),
    Imported(outcome: ImportOutcome.added, :final title) => s.importedAdded(title),
    Imported(outcome: ImportOutcome.renamed, :final title) => s.importedRenamed(title),
    Imported(:final title) => s.importedSame(title),
  };

  // Listed on every build: the session rebuilds the screen after a sync, and the
  // index only rereads files that changed.
  @override
  Widget build(BuildContext context) {
    final s = widget.session.strings;
    if (_archive && Layout.isWide(context)) {
      // Beside the rail, like the notes; Back returns to them.
      return ArchiveScreen(widget.session, back: () => setState(() => _archive = false));
    }
    final notes = widget.session.listNotes();
    // The open note follows the files: archived elsewhere, it closes; else it
    // is read again (one file), so a sync or the assistant shows at once.
    if (_reading case (final open, _)?) {
      final now = notes.where((n) => n.kind == open.kind && n.slug == open.slug).firstOrNull;
      _reading = now == null ? null : (now, widget.session.readNote(now));
    }
    final wide = Layout.isWide(context);
    return Scaffold(
      appBar: AppBar(
        leading: AppMenu.button(context),
        toolbarHeight: !wide && widget.session.driveConnected ? 72 : null,
        title: wide
            ? Text(s.notes)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [Text(s.notes), SyncState(widget.session)],
              ),
        actions: wide ? null : [_listActions(context, notes)],
      ),
      body: Builder(
        builder: (context) {
          final wide = Layout.isWide(context);
          final list = _list(context, notes, wide: wide);
          if (!wide || notes.isEmpty) return list;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 400, child: list),
              const VerticalDivider(width: 1),
              Expanded(child: _reader(context)),
            ],
          );
        },
      ),
    );
  }

  Widget _list(BuildContext context, List<NoteInfo> all, {required bool wide}) {
    final s = widget.session.strings;
    final colors = Theme.of(context).colorScheme;
    if (all.isEmpty) {
      return Column(
        children: [
          if (wide) _listHeader(context, all),
          Expanded(child: _refreshable(_shown(context, all, wide: wide))),
        ],
      );
    }
    final session = widget.session;
    final filtered = [
      for (final note in all)
        if ((session.notesKind ?? note.kind) == note.kind &&
            (session.notesTag == null || note.tags.contains(session.notesTag)))
          note,
    ];
    final searching = _search.text.trim().isNotEmpty;
    final notes = searching ? session.findNotes(_search.text, filtered) : filtered;
    return Column(
      children: [
        if (wide) _listHeader(context, all),
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.m, 0),
          child: TextField(
            key: const Key('notes-search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: s.searchNotes,
              hintStyle: TextStyle(fontSize: 14.5, color: colors.onSurfaceVariant),
              prefixIcon: Icon(Icons.search, size: 20, color: colors.onSurfaceVariant),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: s.clearSearch,
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(_search.clear),
                    ),
            ),
          ),
        ),
        _filters(context, all),
        Expanded(
          child: _refreshable(
            notes.isEmpty
                // Right under the field, where the eye is after typing.
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(Gap.m, Gap.l, Gap.m, 0),
                    children: [
                      Text(
                        searching ? s.noNoteMentions(_search.text.trim()) : s.noFilteredNotes,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  )
                // Coming up only lists notes in `all`, so it follows the filters too.
                : _shown(context, notes, wide: wide, all: filtered),
          ),
        ),
      ],
    );
  }

  /// All, the two kinds, then the eight most used tags (and the chosen one,
  /// even when no note carries it any more); one kind and one tag at a time.
  Widget _filters(BuildContext context, List<NoteInfo> all) {
    final s = widget.session.strings;
    final session = widget.session;
    final tags = _filterTags(all, chosen: session.notesTag);
    return SingleChildScrollView(
      key: const Key('note-filters'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(Gap.m, Gap.xs, Gap.m, 0),
      child: Row(
        children: [
          _chip(
            context,
            s.filterAll,
            selected: session.notesKind == null && session.notesTag == null,
            onTap: () => setState(
              () => session
                ..notesKind = null
                ..notesTag = null,
            ),
          ),
          for (final (kind, label) in [('project', s.filterProjects), ('topic', s.filterTopics)])
            _chip(
              context,
              label,
              selected: session.notesKind == kind,
              onTap: () =>
                  setState(() => session.notesKind = session.notesKind == kind ? null : kind),
            ),
          for (final tag in tags)
            _chip(
              context,
              '#$tag',
              selected: session.notesTag == tag,
              onTap: () => setState(() => session.notesTag = session.notesTag == tag ? null : tag),
            ),
        ],
      ),
    );
  }

  /// The eight most used tags, most used first, then by name; the chosen tag
  /// leads so it is in sight when the screen opens again.
  static List<String> _filterTags(List<NoteInfo> all, {String? chosen}) {
    final counts = <String, int>{};
    for (final note in all) {
      for (final tag in note.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final byUse = counts.keys.toList()
      ..sort((a, b) {
        final more = counts[b]!.compareTo(counts[a]!);
        return more != 0 ? more : a.compareTo(b);
      });
    final tags = byUse.take(8).toList();
    if (chosen != null) {
      tags
        ..remove(chosen)
        ..insert(0, chosen);
    }
    return tags;
  }

  Widget _chip(
    BuildContext context,
    String label, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: Gap.s),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        selectedColor: colors.primary,
        side: selected ? BorderSide(color: colors.primary) : null,
        labelStyle: TextStyle(
          color: selected ? colors.onPrimary : colors.onSurface,
          fontWeight: selected ? FontWeight.w600 : null,
        ),
        materialTapTargetSize: MaterialTapTargetSize.padded,
        onSelected: (_) => onTap(),
      ),
    );
  }

  /// [notes] as cards, or the first-run hint when there are none at all.
  Widget _shown(
    BuildContext context,
    List<NoteInfo> notes, {
    required bool wide,
    List<NoteInfo> all = const [],
  }) {
    final s = widget.session.strings;
    return notes.isEmpty
        ? CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: EmptyState(
                    icon: Icons.description_outlined,
                    title: s.noNotes,
                    actions: [
                      FilledButton.tonal(onPressed: widget.toChat, child: Text(s.goToChat)),
                      OutlinedButton.icon(
                        onPressed: _import,
                        icon: const Icon(Icons.file_open_outlined),
                        label: Text(s.importNotes),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          )
        : _cards(context, notes, wide: wide, all: all);
  }

  /// What is coming, then the pinned notes under their header, then the others
  /// under theirs.
  Widget _cards(
    BuildContext context,
    List<NoteInfo> notes, {
    required bool wide,
    required List<NoteInfo> all,
  }) {
    final s = widget.session.strings;
    final pinned = notes.where((n) => n.pinned).toList();
    final others = notes.where((n) => !n.pinned).toList();
    final now = widget.session.clock().toLocal();
    final today = DateTime(now.year, now.month, now.day);
    // Only notes the list knows, so a row opens the same note a card does.
    final known = {for (final note in all) (note.kind, note.slug): note};
    // Not over search results; and a search typed is not re-read on every key.
    final coming = [
      if (_search.text.trim().isEmpty)
        for (final item in calendarItems(widget.session.paths.notes.path, today: today))
          if (item.todo && !item.day.isBefore(today) && known.containsKey((item.kind, item.slug)))
            item,
    ];
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.m, Gap.l),
      children: [
        if (coming.isNotEmpty)
          _ComingUp(
            coming,
            strings: s,
            open: (item) => _openNote(known[(item.kind, item.slug)]!, wide: wide),
          ),
        if (pinned.isNotEmpty) SectionLabel(s.pinnedNotes, strings: s),
        for (final note in pinned) _card(context, note, wide: wide),
        if (pinned.isNotEmpty && others.isNotEmpty) SectionLabel(s.otherNotes, strings: s),
        for (final note in others) _card(context, note, wide: wide),
      ],
    );
  }

  /// Read once: the app rebuilds on every session change, and a deleted note
  /// must not be read again under its reader.
  void _openNote(NoteInfo note, {required bool wide}) {
    final text = widget.session.readNote(note);
    if (wide) {
      setState(() => _reading = (note, text));
    } else {
      _open(note, text);
    }
  }

  Widget _card(BuildContext context, NoteInfo note, {required bool wide}) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.s),
    child: _NoteRow(
      note,
      strings: widget.session.strings,
      today: widget.session.clock().toLocal(),
      selected: wide && _isOpen(note),
      query: _search.text.trim().isEmpty ? null : _search.text,
      onTap: () => _openNote(note, wide: wide),
    ),
  );

  /// The open note beside the list, or where it will be.
  Widget _reader(BuildContext context) {
    final s = widget.session.strings;
    final Widget content;
    if (_reading case (final note, final text)?) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The note's own heading is its title; above it only its actions.
          Padding(
            padding: const EdgeInsets.fromLTRB(0, Gap.s, Gap.s, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _pin(note, pinned: note.pinned),
                IconButton(
                  tooltip: s.export,
                  icon: const Icon(Icons.ios_share),
                  onPressed: () => _export([note]),
                ),
                IconButton(
                  tooltip: s.delete,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(note),
                ),
              ],
            ),
          ),
          Expanded(
            child: NoteView(
              text,
              folder: p.dirname(notePath(widget.session.paths.notes.path, note.kind, note.slug)),
              strings: widget.session.strings,
              today: widget.session.clock().toLocal(),
              onTodo: (number, text, done) =>
                  unawaited(widget.session.setTodoDone(note, number, text: text, done: done)),
            ),
          ),
        ],
      );
    } else {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: Gap.m),
            Text(
              s.pickNote,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Layout.column),
        child: content,
      ),
    );
  }

  /// The note, read-only, with its own delete button.
  void _open(NoteInfo note, String text) {
    var pinned = note.pinned; // outside the builder, which may run again
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (reader) => Scaffold(
          // The note's own heading is its title: the bar only holds its actions.
          appBar: AppBar(
            actions: [
              StatefulBuilder(
                builder: (context, setPin) =>
                    _pin(note, pinned: pinned, done: () => setPin(() => pinned = !pinned)),
              ),
              IconButton(
                tooltip: widget.session.strings.export,
                icon: const Icon(Icons.ios_share),
                onPressed: () => _export([note]),
              ),
              IconButton(
                tooltip: widget.session.strings.delete,
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  if (await _delete(note) && reader.mounted) Navigator.of(reader).pop();
                },
              ),
            ],
          ),
          // A comfortable reading width on wide windows, and the page follows a
          // checkbox it writes (#512).
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Layout.column),
              child: WritableNoteView(
                widget.session,
                note,
                text,
                folder: p.dirname(notePath(widget.session.paths.notes.path, note.kind, note.slug)),
                strings: widget.session.strings,
                today: widget.session.clock().toLocal(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The app bar's icon colour would hide `isSelected`, so the filled pin names its own.
  Widget _pin(NoteInfo note, {required bool pinned, VoidCallback? done}) => Builder(
    builder: (context) => IconButton(
      tooltip: pinned ? widget.session.strings.unpin : widget.session.strings.pin,
      isSelected: pinned,
      icon: const Icon(Icons.push_pin_outlined),
      selectedIcon: Icon(Icons.push_pin, color: Theme.of(context).colorScheme.primary),
      onPressed: () async {
        if (await widget.session.pinNote(note, pinned: !pinned)) done?.call();
      },
    ),
  );
}

/// The open todos due from today on, the soonest first, at most three; a row
/// opens its note.
class _ComingUp extends StatelessWidget {
  const _ComingUp(this.items, {required this.strings, required this.open});

  final List<DayItem> items;
  final Strings strings;
  final ValueChanged<DayItem> open;

  @override
  Widget build(BuildContext context) {
    final s = strings;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final mono = theme.extension<NoteloreTokens>()!.label.copyWith(
      fontSize: 10,
      letterSpacing: 0.6,
      color: colors.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(top: Gap.s, bottom: Gap.xs),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.only(top: 12, bottom: Gap.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionLabel(
                s.comingUp,
                strings: s,
                padding: const EdgeInsets.fromLTRB(Gap.m, 0, Gap.m, Gap.xs),
                trailing: Text(s.todoCount(items.length), textAlign: TextAlign.end, style: mono),
              ),
              for (final (index, item) in items.take(3).indexed) ...[
                if (index > 0) const Divider(indent: Gap.m, endIndent: Gap.m),
                _row(theme, item, mono),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, DayItem item, TextStyle mono) {
    final colors = theme.colorScheme;
    return InkWell(
      onTap: () => open(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.m, vertical: Gap.s),
        child: Row(
          children: [
            // Grows with large text rather than breaking the day's digits apart.
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 40),
              child: Column(
                children: [
                  Text(
                    '${item.day.day}',
                    softWrap: false,
                    maxLines: 1,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: 20,
                      height: 1,
                      color: colors.primary,
                    ),
                  ),
                  Text(
                    strings.caps(strings.months[item.day.month - 1]),
                    style: mono.copyWith(fontSize: 9, letterSpacing: 1.1),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13.5),
                  ),
                  Text(
                    item.note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11.5,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Picks the notes to export together.
class _ChooseNotes extends StatefulWidget {
  const _ChooseNotes(this.notes, this.strings);

  final List<NoteInfo> notes;
  final Strings strings;

  @override
  State<_ChooseNotes> createState() => _ChooseNotesState();
}

class _ChooseNotesState extends State<_ChooseNotes> {
  final _chosen = <NoteInfo>{};

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return AlertDialog(
      title: Text(s.chooseNotes),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final note in widget.notes)
              CheckboxListTile(
                title: Text(note.title),
                value: _chosen.contains(note),
                onChanged: (on) => setState(() => on! ? _chosen.add(note) : _chosen.remove(note)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.cancel)),
        FilledButton(
          onPressed: _chosen.isEmpty
              ? null
              : () => Navigator.pop(context, [
                  for (final note in widget.notes)
                    if (_chosen.contains(note)) note,
                ]),
          child: Text(s.next),
        ),
      ],
    );
  }
}

/// What was deleted, newest first; each opens read-only with Restore.
class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen(this.session, {this.back, super.key});

  final Session session;

  /// In a pane rather than a page of its own: what its Back does.
  final VoidCallback? back;

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  /// The archived note open in the pane, on a wide window; read once.
  (ArchivedNote, String)? _reading;

  Future<void> _restore(ArchivedNote archived, VoidCallback close) async {
    final s = widget.session.strings;
    final messenger = ScaffoldMessenger.of(context);
    final done = await widget.session.restoreArchived(archived);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(done ? s.restored(archived.title) : s.restoreTaken(archived.title))),
      );
    if (done) close();
    if (mounted) setState(() {});
  }

  /// Asks, then deletes [archived] for good; true when it went.
  Future<bool> _deleteForever(ArchivedNote archived) async {
    final s = widget.session.strings;
    final messenger = ScaffoldMessenger.of(context);
    final title = s.archivedTitle(archived);
    if (!await _confirm(s.deleteForeverTitle(title), s.deleteForeverBody, s.deleteForever)) {
      return false;
    }
    await widget.session.deleteArchived(archived);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s.deletedForever(title))));
    if (mounted) setState(() {});
    return true;
  }

  Future<void> _empty(int count) async {
    final s = widget.session.strings;
    final messenger = ScaffoldMessenger.of(context);
    if (!await _confirm(s.emptyArchive, s.emptyArchiveBody(count), s.emptyArchive)) return;
    final gone = await widget.session.emptyArchive();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s.archiveEmptied(gone))));
    if (mounted) setState(() {});
  }

  /// A destructive step, said plainly, with its button in the error colour.
  Future<bool> _confirm(String title, String body, String action) async {
    final s = widget.session.strings;
    final colors = Theme.of(context).colorScheme;
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        icon: Icon(Icons.delete_forever_outlined, color: colors.error),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: Text(s.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            ),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return sure ?? false;
  }

  // Read once: a restore moves the file while the app rebuilds this route.
  void _open(ArchivedNote archived) {
    final text = widget.session.readArchived(archived);
    if (widget.back != null) return setState(() => _reading = (archived, text));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (reader) => _reader(archived, text, () => Navigator.of(reader).pop()),
      ),
    );
  }

  /// [archived], read-only, with Restore and Delete forever in its bar, clear
  /// of the notices they leave. Its heading is its title; the bar names only
  /// archived entries, which the heading alone would not say.
  Widget _reader(ArchivedNote archived, String text, VoidCallback close) {
    final s = widget.session.strings;
    return Scaffold(
      appBar: AppBar(
        leading: widget.back == null ? null : BackButton(onPressed: close),
        title: archived.entries ? Text(s.archivedTitle(archived)) : null,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.restore),
            label: Text(s.restore),
            onPressed: () => _restore(archived, close),
          ),
          IconButton(
            tooltip: s.deleteForever,
            icon: const Icon(Icons.delete_forever_outlined),
            onPressed: () async {
              if (await _deleteForever(archived)) close();
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Layout.column),
          child: NoteView(
            text,
            // As it was: its images were linked from where it lived.
            folder: p.dirname(p.join(widget.session.paths.notes.path, archived.original)),
            strings: s,
            today: widget.session.clock().toLocal(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session.strings;
    if (widget.back case final back?) {
      // In a pane, not a route: the system's back steps out of it too.
      void close() => setState(() => _reading = null);
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (_, _) => _reading == null ? back() : close(),
        child: switch (_reading) {
          (final archived, final text) => _reader(archived, text, close),
          null => _list(context, s),
        },
      );
    }
    return _list(context, s);
  }

  Widget _list(BuildContext context, Strings s) {
    final archived = widget.session.listArchived();
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: widget.back == null ? null : BackButton(onPressed: widget.back),
        title: Text(s.archive),
        actions: [
          if (archived.isNotEmpty)
            PopupMenuButton<String>(
              key: const Key('archive-more'),
              tooltip: s.archiveActions,
              onSelected: (_) => _empty(archived.length),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'empty',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep_outlined, color: colors.error),
                      const SizedBox(width: Gap.s),
                      Expanded(
                        child: Text(s.emptyArchive, style: TextStyle(color: colors.error)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      // A readable width on a wide window, like the reader's, centred in its
      // pane as the other panes are (#715).
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Layout.column),
          child: archived.isEmpty
              ? Center(
                  child: EmptyState(icon: Icons.inventory_2_outlined, title: s.archiveEmpty),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.m, Gap.l),
                  itemCount: archived.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Gap.s),
                  itemBuilder: (context, index) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(s.archivedTitle(archived[index])),
                      subtitle: Text(
                        s.archivedOn(
                          // A folder that is not a date (made by hand) shows as named.
                          switch (DateTime.tryParse(archived[index].archivedOn)) {
                            null => archived[index].archivedOn,
                            final day => s.shortDate(day, widget.session.clock().toLocal()),
                          },
                        ),
                      ),
                      onTap: () => _open(archived[index]),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: s.restore,
                            icon: const Icon(Icons.restore),
                            onPressed: () => _restore(archived[index], () {}),
                          ),
                          PopupMenuButton<String>(
                            key: ValueKey('archive-note-more-${archived[index].original}'),
                            tooltip: s.moreNoteActions,
                            onSelected: (_) => _deleteForever(archived[index]),
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_forever_outlined, color: colors.error),
                                    const SizedBox(width: Gap.s),
                                    Expanded(
                                      child: Text(
                                        s.deleteForever,
                                        style: TextStyle(color: colors.error),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// One note in the list: its title, newest words (or, under a [query], the
/// line that matched, its words marked), kind, date, tags and open todos (#773).
class _NoteRow extends StatelessWidget {
  const _NoteRow(
    this.note, {
    required this.strings,
    required this.today,
    required this.selected,
    required this.query,
    required this.onTap,
  });

  final NoteInfo note;
  final Strings strings;
  final DateTime today;
  final bool selected;
  final String? query;
  final VoidCallback onTap;

  /// [text] with the words of [query] in [mark].
  static TextSpan _marked(String text, String query, TextStyle mark) {
    var at = 0;
    return TextSpan(
      children: [
        for (final (start, end) in matchRanges(text, query)) ...[
          if (start > at) TextSpan(text: text.substring(at, start)),
          TextSpan(text: text.substring(start, at = end), style: mark),
        ],
        if (at < text.length) TextSpan(text: text.substring(at)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = strings;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant);
    return Card(
      // The open note is told by its edge in the accent.
      shape: selected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: colors.primary),
            )
          : null,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 4, Gap.m, 4),
        horizontalTitleGap: 12,
        titleAlignment: ListTileTitleAlignment.top,
        selectedColor: colors.onSurface,
        // The kind at a glance: a folder for a project, a tag for a topic.
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: colors.primaryContainer,
          foregroundColor: colors.primary,
          child: Icon(
            note.kind == 'project' ? Icons.folder_outlined : Icons.sell_outlined,
            size: 18,
          ),
        ),
        title: Text(
          note.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(fontSize: 16, height: 1.25),
        ),
        isThreeLine: note.excerpt.isNotEmpty,
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (note.excerpt.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Gap.xs),
                child: Text.rich(
                  query == null
                      ? TextSpan(text: note.excerpt)
                      : _marked(
                          note.excerpt,
                          query!,
                          TextStyle(color: colors.primary, fontWeight: FontWeight.w600),
                        ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: muted?.copyWith(fontSize: 13, height: 1.4),
                ),
              ),
            const SizedBox(height: Gap.xs),
            Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      s.noteSubtitle(
                        note.kind,
                        note.updated == null ? '?' : s.shortDate(note.updated!, today),
                      ),
                      if (note.tags.isNotEmpty) note.tags.map((tag) => '#$tag').join(' '),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                ),
                if (note.openTodos > 0)
                  Semantics(
                    container: true,
                    label: s.openTodos(note.openTodos),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.checklist, size: 16, color: colors.primary),
                        const SizedBox(width: Gap.xs),
                        Text('${note.openTodos}', style: muted?.copyWith(color: colors.primary)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
        selected: selected,
        onTap: onTap,
      ),
    );
  }
}
