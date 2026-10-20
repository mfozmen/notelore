import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;

import 'session.dart' show withoutFrontMatter;
import 'strings.dart';
import 'theme.dart';
import 'web_link.dart';

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
    super.key,
  });

  final String source;
  final String folder;
  final Strings strings;
  final DateTime today;

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
        onTapLink: (_, href, _) => openWebLink(href),
        imageBuilder: _image,
        styleSheet: _sheet(Theme.of(context)),
      );
    }
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.m, Gap.m, Gap.m, Gap.l),
        children: [
          ..._header(context, note),
          if (note.preamble.join('\n').trim() case final intro when intro.isNotEmpty) ...[
            const SizedBox(height: Gap.m),
            _markdown(intro),
          ],
          for (final section in _ordered(note.sections))
            if (_hasContent(section)) ...[
              const SizedBox(height: Gap.l),
              _Heading(section.heading),
              const SizedBox(height: Gap.s),
              ..._section(context, section),
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

  /// Inline Markdown: bold, links and images work in every line.
  Widget _markdown(String text, {TextStyle? style}) => Builder(
    builder: (context) => MarkdownBody(
      data: text,
      onTapLink: (_, href, _) => openWebLink(href),
      imageBuilder: _image,
      styleSheet: _sheet(Theme.of(context)).copyWith(p: style),
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
      Text(note.title, style: theme.textTheme.headlineSmall),
      const SizedBox(height: Gap.s),
      Wrap(
        spacing: Gap.s,
        runSpacing: Gap.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (note.meta['kind'] case final kind?)
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(Gap.s),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.s, vertical: Gap.xs / 2),
                child: Text(
                  strings.noteKind('$kind'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ),
          Text(
            [
              if (tags.isNotEmpty) tags.join(' '),
              if (updated != null) strings.updatedOn(_date(updated)),
            ].join('  ·  '),
            style: muted,
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
        'todo' => _todos(context, section.entries.whereType<Todo>().toList()),
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
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final earlier = decisions.where((d) => d.superseded != null).toList();
    return [
      for (final decision in decisions.where((d) => d.superseded == null))
        Card.filled(
          margin: const EdgeInsets.only(bottom: Gap.s),
          color: theme.colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(Gap.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        decision.topic,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    Text(_date(decision.date), style: muted),
                  ],
                ),
                const SizedBox(height: Gap.xs),
                _markdown(decision.value, style: theme.textTheme.titleMedium),
                if (decision.reason case final reason?) ...[
                  const SizedBox(height: Gap.xs),
                  _markdown(
                    reason,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
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

  List<Widget> _todos(BuildContext context, List<Todo> todos) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final open = todos.where((t) => !t.done).toList()..sort((a, b) => a.date.compareTo(b.date));
    final done = todos.where((t) => t.done);
    final day = DateTime(today.year, today.month, today.day);
    return [
      for (final todo in [...open, ...done])
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Shown, not tapped: no checkbox that looks like a control.
              Icon(
                todo.done ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 20,
                color: todo.done ? colors.outline : colors.onSurfaceVariant,
              ),
              const SizedBox(width: Gap.s),
              Expanded(
                child: _markdown(
                  todo.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: todo.done ? colors.onSurfaceVariant : null,
                    decoration: todo.done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              const SizedBox(width: Gap.s),
              _todoDate(theme, todo, late: !todo.done && todo.date.isBefore(day)),
            ],
          ),
        ),
    ];
  }

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
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                passed ? Icons.history : Icons.notifications_outlined,
                size: 20,
                color: passed ? colors.outline : colors.primary,
              ),
              const SizedBox(width: Gap.s),
              Expanded(
                child: _markdown(
                  reminder.text.replaceAll('\n  ', '\n'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: passed ? colors.onSurfaceVariant : null,
                  ),
                ),
              ),
              const SizedBox(width: Gap.s),
              Text(() {
                final when = [_date(reminder.date), ?reminder.time].join(' · ');
                return passed ? strings.reminderPassed(when) : when;
              }(), style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
            ],
          ),
        ),
    ];
  }

  /// A late one says so, in words and in the error colour.
  Widget _todoDate(ThemeData theme, Todo todo, {required bool late}) => Text(
    late ? strings.overdue(_date(todo.date)) : _date(todo.date),
    style: theme.textTheme.bodySmall?.copyWith(
      color: late ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
    ),
  );

  /// Newest day first, each day's entries in the order written, on a rail.
  /// A date carries no year; the year heads its days when it is not this one.
  List<Widget> _notes(BuildContext context, List<Entry> entries) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
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
                    style: muted,
                  ),
                ),
              ),
              VerticalDivider(width: Gap.m, thickness: 2, color: theme.colorScheme.outlineVariant),
              const SizedBox(width: Gap.s),
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

/// A section's own heading, as the note names it.
class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
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
        _card(context, const Icon(Icons.broken_image_outlined), s.imageFailed);
    if (!uri.hasScheme) {
      final path = p.normalize(p.join(widget.folder, Uri.decodeComponent(uri.path)));
      // Only inside the notes folder (the note's folder's parent): a note never probes the disk.
      if (!p.isWithin(p.dirname(widget.folder), path)) return failed(context, null, null);
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
      Icon(Icons.image_outlined, color: Theme.of(context).colorScheme.primary),
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
