import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;

import 'icons.dart';
import 'section_label.dart';
import 'session.dart' show Session, withoutFrontMatter;
import 'soft.dart';
import 'strings.dart';
import 'theme.dart';
import 'web_link.dart';

/// Opens [note], read as [text], as a page of its own with its title on top.
void pushNote(BuildContext context, Session session, NoteInfo note, String text) =>
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => NotePage(session, note, text)));

/// [note], read as [text], as a page with its title on top.
class NotePage extends StatelessWidget {
  const NotePage(this.session, this.note, this.text, {super.key});

  final Session session;
  final NoteInfo note;
  final String text;

  @override
  Widget build(BuildContext context) {
    final now = session.clock().toLocal();
    return Scaffold(
      appBar: AppBar(leading: softBack(context), title: Text(note.title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Layout.column),
          child: WritableNoteView(
            session,
            note,
            text,
            folder: p.dirname(notePath(session.paths.notes.path, note.kind, note.slug)),
            strings: session.strings,
            today: DateTime(now.year, now.month, now.day),
          ),
        ),
      ),
    );
  }
}

/// A note page that writes its todo checkboxes and shows the new line at once.
class WritableNoteView extends StatefulWidget {
  const WritableNoteView(
    this.session,
    this.note,
    this.text, {
    required this.folder,
    required this.strings,
    required this.today,
    this.onOpen,
    super.key,
  });

  final Session session;
  final NoteInfo note;
  final String text;
  final String folder;
  final Strings strings;
  final DateTime today;

  /// Opens a related note; without it the page lists none.
  final ValueChanged<NoteInfo>? onOpen;

  @override
  State<WritableNoteView> createState() => _WritableNoteViewState();
}

class _WritableNoteViewState extends State<WritableNoteView> {
  late var _text = widget.text;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_changed);
  }

  /// A sync or the assistant changed the note: show its new words (#512).
  void _changed() {
    final next = _read();
    if (next != null && mounted) setState(() => _text = next);
  }

  /// The note's file, or null when it is gone since it opened.
  String? _read() {
    try {
      return widget.session.readNote(widget.note);
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _toggle(int number, String text, bool done) async {
    await widget.session.setTodoDone(widget.note, number, text: text, done: done);
    if (!mounted) return;
    final next = _read();
    if (next != null) setState(() => _text = next);
  }

  @override
  void dispose() {
    widget.session.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NoteView(
    _text,
    folder: widget.folder,
    strings: widget.strings,
    today: widget.today,
    onTodo: (number, text, done) => unawaited(_toggle(number, text, done)),
    related: widget.onOpen == null ? const [] : widget.session.relatedNotes(widget.note),
    onOpen: widget.onOpen,
    onFile: widget.session.openAttachment,
  );
}

/// [uri]'s path decoded, or null when its escapes are not UTF-8 (`%C3`):
/// [Uri.tryParse] lets those through, and decoding them throws.
String? _decoded(Uri uri) {
  try {
    return Uri.decodeComponent(uri.path);
  } on FormatException {
    return null;
  }
}

/// A note as a page (#426): its title and what it is, then each known section
/// in its own form: decisions as cards, todos as checkboxes, notes as a dated
/// timeline. The file stays plain Markdown; only the reading changes. A file
/// the parser cannot read shows as Markdown. What is coming (reminders, todos)
/// comes before the notes (#430). Images resolve against [folder], the note's
/// own; [today] (with its time) marks late todos and past reminders.
class NoteView extends StatelessWidget {
  const NoteView(
    this.source, {
    required this.folder,
    required this.strings,
    required this.today,
    this.onTodo,
    this.related = const [],
    this.onOpen,
    this.onFile,
    super.key,
  });

  final String source;

  /// Shown at the foot as cards that call [onOpen]; none without it.
  final List<NoteInfo> related;
  final ValueChanged<NoteInfo>? onOpen;
  final String folder;
  final Strings strings;
  final DateTime today;

  /// Opens a file the note links by a relative path (a kept original), given
  /// its path resolved against [folder]; the opener checks where it leads.
  final ValueChanged<String>? onFile;

  void _link(String? href) {
    final uri = Uri.tryParse(href ?? '');
    if (uri != null && !uri.hasScheme && uri.path.isNotEmpty) {
      if (_decoded(uri) case final path?) onFile?.call(p.join(folder, path));
    } else {
      openWebLink(href);
    }
  }

  /// Called with a todo's number in the note and its new done state; without
  /// it (the archive), todos are marks, not controls.
  final void Function(int number, String text, bool done)? onTodo;

  @override
  Widget build(BuildContext context) {
    final Note note;
    try {
      note = parse(source);
    } on NotANote {
      return Markdown(
        data: withoutFrontMatter(source),
        selectable: true,
        padding: const EdgeInsets.all(Gap.m),
        onTapLink: (_, href, _) => _link(href),
        imageBuilder: _image,
        styleSheet: _sheet(Theme.of(context)),
      );
    }
    return SelectionArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          Gap.m,
          Gap.m,
          Gap.m,
          Gap.l + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          ..._header(context, note),
          if (note.preamble.join('\n').trim() case final intro when intro.isNotEmpty) ...[
            const SizedBox(height: Gap.m),
            _markdown(intro),
          ],
          for (final section in _ordered(note.sections))
            if (_hasContent(section)) ...[
              SectionLabel(
                section.heading,
                strings: strings,
                padding: const EdgeInsets.only(top: Gap.l, bottom: Gap.s),
              ),
              ..._section(context, section),
            ],
          if (onOpen case final open? when related.isNotEmpty) ...[
            SectionLabel(
              strings.relatedNotes,
              strings: strings,
              padding: const EdgeInsets.only(top: Gap.l, bottom: Gap.s),
            ),
            for (final note in related)
              _RelatedCard(note, strings: strings, today: today, onTap: () => open(note)),
          ],
        ],
      ),
    );
  }

  /// Whether [section] has anything to read: a heading alone says nothing.
  static bool _hasContent(Section section) =>
      section.entries.any((e) => e is! Raw || e.text.trim().isNotEmpty);

  /// The sections as the file has them, but Reminders and Todo right before
  /// Notes: what is coming first, what happened after.
  static List<Section> _ordered(List<Section> sections) {
    bool coming(Section s) => s.key == 'reminders' || s.key == 'todo';
    final ahead = [
      ...sections.where((s) => s.key == 'reminders'),
      ...sections.where((s) => s.key == 'todo'),
    ];
    final rest = sections.where((s) => !coming(s)).toList();
    final notes = rest.indexWhere((s) => s.key == 'notes');
    return rest..insertAll(notes < 0 ? rest.length : notes, ahead);
  }

  Widget _image(Uri uri, String? title, String? alt) => _NoteImage(uri, alt ?? '', folder, strings);

  String _date(DateTime date) => strings.shortDate(date, today);

  /// A date beside an entry: small mono, muted.
  static TextStyle _mono(ThemeData theme) => theme.extension<NoteloreTokens>()!.label.copyWith(
    fontSize: 10,
    letterSpacing: 0.6,
    color: theme.colorScheme.onSurfaceVariant,
  );

  /// Inline Markdown: bold, links and images work in every line.
  Widget _markdown(String text, {TextStyle? style, Color? link}) => Builder(
    builder: (context) => MarkdownBody(
      data: text,
      onTapLink: (_, href, _) => _link(href),
      imageBuilder: _image,
      styleSheet: _sheet(Theme.of(context)).copyWith(
        p: style,
        a: link == null ? null : TextStyle(color: link),
      ),
    ),
  );

  /// Links in the theme's colour, not the package's blue.
  static MarkdownStyleSheet _sheet(ThemeData theme) =>
      MarkdownStyleSheet.fromTheme(theme).copyWith(a: TextStyle(color: theme.colorScheme.primary));

  List<Widget> _header(BuildContext context, Note note) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final tags = [for (final tag in (note.meta['tags'] as List?) ?? const []) '#$tag'];
    // The front matter reader hands a date back as one; anything else is not shown.
    final updated = note.meta['updated'] is DateTime ? note.meta['updated']! as DateTime : null;
    return [
      Text(
        note.title,
        style: theme.textTheme.headlineSmall?.copyWith(
          fontSize: 28,
          height: 1.12,
          letterSpacing: -0.56,
        ),
      ),
      const SizedBox(height: Gap.s),
      Wrap(
        spacing: Gap.s,
        runSpacing: Gap.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (note.meta['kind'] case final kind?)
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(Gap.s),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.s, vertical: 2),
                child: Text(
                  strings.noteKind('$kind'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          Text(
            [
              if (tags.isNotEmpty) tags.join(' '),
              if (updated != null) strings.updatedOn(_date(updated)),
            ].join('  ·  '),
            style: muted?.copyWith(fontSize: 12.5),
          ),
        ],
      ),
    ];
  }

  List<Widget> _section(BuildContext context, Section section) {
    final raw = [
      for (final entry in section.entries)
        if (entry is Raw && entry.text.trim().isNotEmpty) entry.text,
    ];
    return [
      ...switch (section.key) {
        'decisions' => _decisions(context, section.entries.whereType<Decision>().toList()),
        'todo' => _todos(context, section.entries),
        'notes' => _notes(context, section.entries.whereType<Entry>().toList()),
        'reminders' => _reminders(context, section.entries.whereType<Reminder>().toList()),
        // A section someone wrote by hand: as written.
        _ => [_markdown(section.entries.map((e) => e.render()).join('\n'))],
      },
      if (section.key != null && raw.isNotEmpty) _markdown(raw.join('\n')),
    ];
  }

  List<Widget> _decisions(BuildContext context, List<Decision> decisions) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NoteloreTokens>()!;
    final earlier = decisions.where((d) => d.superseded != null).toList();
    return [
      for (final decision in decisions.where((d) => d.superseded == null))
        HotCard(
          margin: const EdgeInsets.only(bottom: Gap.s),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.m, vertical: Gap.s + Gap.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.caps(decision.topic),
                        semanticsLabel: decision.topic,
                        style: tokens.label.copyWith(color: tokens.hotLabel),
                      ),
                    ),
                    Text(
                      _date(decision.date),
                      style: _mono(theme).copyWith(color: tokens.hotLabel),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.xs),
                _markdown(
                  decision.value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 20,
                    height: 1.25,
                    color: tokens.hotValue,
                  ),
                  link: tokens.hotLink,
                ),
                if (decision.reason case final reason?) ...[
                  const SizedBox(height: Gap.xs),
                  _markdown(
                    reason,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13.5,
                      color: tokens.hotReason,
                    ),
                    link: tokens.hotLink,
                  ),
                ],
              ],
            ),
          ),
        ),
      if (earlier.isNotEmpty)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: Gap.s),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          expandedAlignment: Alignment.centerLeft,
          shape: const Border(),
          collapsedShape: const Border(),
          iconColor: theme.colorScheme.onSurfaceVariant,
          collapsedIconColor: theme.colorScheme.onSurfaceVariant,
          title: Text(strings.earlierDecisions(earlier.length), style: theme.textTheme.bodyMedium),
          children: [
            for (final decision in earlier)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                child: Text.rich(
                  TextSpan(
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    children: [
                      TextSpan(
                        text: '${decision.topic}: ${decision.value}',
                        style: const TextStyle(decoration: TextDecoration.lineThrough),
                      ),
                      TextSpan(
                        text:
                            '  ·  ${_date(decision.date)}, '
                            '${strings.supersededOn(_date(decision.superseded!))}',
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
    ];
  }

  List<Widget> _todos(BuildContext context, List<NoteEntry> entries) {
    final theme = Theme.of(context);
    final numbered = [for (final (i, entry) in entries.whereType<Todo>().indexed) (i + 1, entry)];
    // Undated ones have no deadline: after the dated ones.
    final undated = DateTime(9999);
    final open = numbered.where((t) => !t.$2.done).toList()
      ..sort((a, b) => (a.$2.date ?? undated).compareTo(b.$2.date ?? undated));
    final done = numbered.where((t) => t.$2.done);
    final day = DateTime(today.year, today.month, today.day);
    return [
      for (final (number, todo) in [...open, ...done]) _todoRow(theme, number, todo, day),
    ];
  }

  /// A checkbox, or (no [onTodo]) a mark: open ones edged in the accent, late
  /// ones in the error colour, done ones muted.
  Widget _todoMark(ColorScheme colors, int number, Todo todo, {required bool late}) =>
      switch (onTodo) {
        final onTodo? => Checkbox(
          // A fixed 48 dp box on every platform, so _row can pull its 18 dp square to the edge.
          materialTapTargetSize: MaterialTapTargetSize.padded,
          visualDensity: VisualDensity.standard,
          value: todo.done,
          side: BorderSide(color: late ? colors.error : colors.primary, width: 2),
          fillColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? colors.onSurfaceVariant : null,
          ),
          checkColor: colors.surface,
          onChanged: (done) => onTodo(number, todo.text, done ?? false),
        ),
        null => Icon(
          todo.done ? AppIcons.checked : AppIcons.unchecked,
          size: 18,
          color: todo.done ? colors.outline : colors.onSurfaceVariant,
        ),
      };

  Widget _todoRow(ThemeData theme, int number, Todo todo, DateTime day) {
    final colors = theme.colorScheme;
    final late = !todo.done && (todo.date?.isBefore(day) ?? false);
    final row = _row(
      mark: _todoMark(colors, number, todo, late: late),
      // The Checkbox's 48 dp box centres its 18 dp square.
      inset: onTodo == null ? 0 : 15,
      text: _markdown(
        todo.text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: todo.done ? colors.onSurfaceVariant : null,
          decoration: todo.done ? TextDecoration.lineThrough : null,
        ),
      ),
      date: _todoDate(theme, todo, late: late),
    );
    return MergeSemantics(
      child: switch (onTodo) {
        // The checkbox already is the row's one toggle for a screen reader.
        final onTodo? => Material(
          type: MaterialType.transparency,
          child: InkWell(
            excludeFromSemantics: true,
            canRequestFocus: false,
            onTap: () => onTodo(number, todo.text, !todo.done),
            child: row,
          ),
        ),
        null => row,
      },
    );
  }

  /// A todo or reminder row, at least 48 dp tall: [mark] on the page's edge,
  /// the text 26 dp in, the date at the right. [inset] is the empty space
  /// left of what [mark] paints; that space hangs outside the row.
  static Widget _row({
    required Widget mark,
    double inset = 0,
    required Widget text,
    required Widget date,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 18 + Gap.s,
        height: 48,
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: 0,
          minHeight: 0,
          maxWidth: 48,
          maxHeight: 48,
          child: Transform.translate(offset: Offset(-inset, 0), child: mark),
        ),
      ),
      Expanded(
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: text),
      ),
      const SizedBox(width: Gap.s),
      Padding(padding: const EdgeInsets.only(top: 12), child: date),
    ],
  );

  /// Coming ones by day and time, past ones after them, saying so in words
  /// and with their own icon. A reminder with no time counts until its day ends.
  List<Widget> _reminders(BuildContext context, List<Reminder> reminders) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    String key(Reminder r) => '${isoDate(r.date)} ${r.time ?? '24:00'}';
    final now =
        '${isoDate(today)} '
        '${today.hour.toString().padLeft(2, '0')}:${today.minute.toString().padLeft(2, '0')}';
    final sorted = [...reminders]..sort((a, b) => key(a).compareTo(key(b)));
    final coming = sorted.where((r) => key(r).compareTo(now) >= 0);
    final past = sorted.where((r) => key(r).compareTo(now) < 0);
    return [
      for (final (reminder, passed) in [
        for (final r in coming) (r, false),
        for (final r in past.toList().reversed) (r, true),
      ])
        _row(
          mark: Icon(
            passed ? AppIcons.history : AppIcons.notifications,
            size: 18,
            color: passed ? colors.outline : colors.primary,
          ),
          text: _markdown(
            reminder.text.replaceAll('\n  ', '\n'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: passed ? colors.onSurfaceVariant : null,
            ),
          ),
          date: Text(() {
            final when = [_date(reminder.date), ?reminder.time].join(' · ');
            return passed ? strings.reminderPassed(when) : when;
          }(), style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
        ),
    ];
  }

  /// A late one says so, in words and in the error colour.
  Widget _todoDate(ThemeData theme, Todo todo, {required bool late}) => switch (todo.date) {
    final date? => Text(
      late ? strings.overdue(_date(date)) : _date(date),
      style: theme.textTheme.bodySmall?.copyWith(
        color: late ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
      ),
    ),
    null => const SizedBox.shrink(),
  };

  /// Newest day first, each day's entries in the order written, on a rail.
  /// A date carries no year; the year heads its days when it is not this one.
  List<Widget> _notes(BuildContext context, List<Entry> entries) {
    final theme = Theme.of(context);
    final days = <DateTime, List<Entry>>{};
    for (final entry in entries) {
      days.putIfAbsent(entry.date, () => []).add(entry);
    }
    final newest = days.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
    return [
      for (final (index, MapEntry(key: date, value: texts)) in newest.indexed) ...[
        if (date.year != (index == 0 ? today.year : newest[index - 1].key.year))
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.s),
            child: Text('${date.year}', style: theme.textTheme.labelLarge),
          ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 64,
                child: Padding(
                  // On the first line's baseline.
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    strings.shortDate(date, date),
                    maxLines: 1,
                    softWrap: false,
                    style: _mono(theme),
                  ),
                ),
              ),
              VerticalDivider(width: 2, thickness: 2, color: theme.colorScheme.outlineVariant),
              const SizedBox(width: Gap.m),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: index == newest.length - 1 ? 0 : Gap.m),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in texts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Gap.xs),
                          // Continuation lines are indented in the file.
                          child: _markdown(entry.text.replaceAll('\n  ', '\n')),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ];
  }
}

/// A related note, smaller than its row in the notes list: its kind, title and
/// when it changed.
class _RelatedCard extends StatelessWidget {
  const _RelatedCard(this.note, {required this.strings, required this.today, required this.onTap});

  final NoteInfo note;
  final Strings strings;
  final DateTime today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final updated = note.updated;
    return Card(
      margin: const EdgeInsets.only(bottom: Gap.s),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 0, Gap.s, 0),
        horizontalTitleGap: 12,
        leading: CircleAvatar(
          radius: 14,
          backgroundColor: colors.primaryContainer,
          foregroundColor: colors.primary,
          child: Icon(note.kind == 'project' ? AppIcons.folder : AppIcons.tag, size: 16),
        ),
        title: Text(
          note.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(fontSize: 15, height: 1.25),
        ),
        subtitle: Text(
          [
            strings.noteSubtitle(
              note.kind,
              updated == null ? '?' : strings.shortDate(updated, today),
            ),
            if (note.tags.isNotEmpty) note.tags.map((tag) => '#$tag').join(' '),
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        trailing: Icon(AppIcons.chevronRight, color: colors.onSurfaceVariant),
        onTap: onTap,
      ),
    );
  }
}

/// An image in a note. One on the device shows; a remote one waits for a tap:
/// a planted image's address could carry the note away (#311, #339).
class _NoteImage extends StatefulWidget {
  const _NoteImage(this.uri, this.alt, this.folder, this.s);

  final Uri uri;
  final String alt;
  final String folder;
  final Strings s;

  @override
  State<_NoteImage> createState() => _NoteImageState();
}

class _NoteImageState extends State<_NoteImage> {
  var _shown = false;

  @override
  Widget build(BuildContext context) {
    final uri = widget.uri;
    final s = widget.s;
    Widget failed(BuildContext context, _, _) =>
        _card(context, const Icon(AppIcons.brokenImage), s.imageFailed);
    if (!uri.hasScheme) {
      final decoded = _decoded(uri);
      final path = decoded == null ? null : p.normalize(p.join(widget.folder, decoded));
      // Only inside the notes folder (the note's folder's parent): a note never probes the disk.
      if (path == null || !p.isWithin(p.dirname(widget.folder), path)) {
        return failed(context, null, null);
      }
      return Image.file(File(path), semanticLabel: widget.alt, errorBuilder: failed);
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') return Text(widget.alt);
    if (_shown) {
      return Image.network(
        '$uri',
        semanticLabel: widget.alt,
        errorBuilder: failed,
        // The same box while it comes, so the tap never seems to do nothing.
        loadingBuilder: (context, image, progress) => progress == null
            ? image
            : _card(
                context,
                const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                '',
              ),
      );
    }
    return _card(
      context,
      Icon(AppIcons.image, color: Theme.of(context).colorScheme.primary),
      s.tapToShow,
      onTap: () => setState(() => _shown = true),
    );
  }

  /// The box an image stands in: its words, where it comes from, and [state].
  Widget _card(BuildContext context, Widget leading, String state, {VoidCallback? onTap}) {
    final theme = Theme.of(context);
    final host = widget.uri.host;
    final line = [if (host.isNotEmpty) host, if (state.isNotEmpty) state].join(' · ');
    return Semantics(
      button: onTap != null,
      child: Card.outlined(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.m, vertical: Gap.s),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  leading,
                  const SizedBox(width: Gap.s),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.alt.isNotEmpty) Text(widget.alt),
                        Text(
                          line,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
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
      ),
    );
  }
}
