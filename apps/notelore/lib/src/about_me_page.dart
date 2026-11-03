import 'package:flutter/material.dart';
import 'package:notelore_core/notelore_core.dart';

import 'app.dart' show AppMenu;
import 'session.dart';
import 'theme.dart';

/// What the person told about themselves, by section (#671), a place of its
/// own beside Notes (#669). The cloud switch stays in Settings; [privacy] opens it.
class AboutMeScreen extends StatelessWidget {
  const AboutMeScreen(this.session, {required this.privacy, super.key});

  final Session session;
  final VoidCallback privacy;

  Future<void> _edit(BuildContext context, [({String section, String fact})? old]) =>
      showDialog<void>(context: context, builder: (_) => _FactDialog(session, old));

  Future<void> _delete(BuildContext context, String fact, String section) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await session.forgetFact(fact);
    } on ArgumentError {
      return; // already gone on another device; the list has caught up
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            session.strings.factRemoved(fact),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          action: SnackBarAction(
            label: session.strings.undo,
            onPressed: () => session.rememberFact(fact, section: section),
          ),
        ),
      );
  }

  // Its own messenger: an Undo is then laid out by this scaffold, clear of the add button.
  @override
  Widget build(BuildContext context) => ScaffoldMessenger(
    child: ListenableBuilder(listenable: session, builder: _page),
  );

  Widget _page(BuildContext context, Widget? _) {
    final s = session.strings;
    final theme = Theme.of(context);
    final entries = session.aboutMeEntries();
    final wide = Layout.isWide(context);
    final add = Builder(
      builder: (context) => wide
          ? FilledButton.tonalIcon(
              icon: const Icon(Icons.add),
              label: Text(s.addFact),
              onPressed: () => _edit(context),
            )
          : FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: Text(s.addFact),
              onPressed: () => _edit(context),
            ),
    );
    return Scaffold(
      appBar: AppBar(leading: AppMenu.button(context), title: Text(s.aboutMeSection)),
      floatingActionButton: wide ? null : add,
      body: Builder(
        builder: (context) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Layout.column),
            child: ListView(
              // Room under the last row for the button that floats over it on a phone.
              padding: EdgeInsets.only(top: Gap.s, bottom: wide ? Gap.l : 96),
              children: [
                if (entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Gap.m, Gap.l, Gap.m, Gap.m),
                    child: Column(
                      children: [
                        Icon(Icons.person_outline, size: 48, color: theme.colorScheme.primary),
                        const SizedBox(height: Gap.m),
                        Text(
                          s.aboutMeEmpty,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                for (final section in aboutMeSections.keys)
                  if (entries.where((e) => e.section == section).toList() case final mine
                      when mine.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Gap.m, Gap.l, Gap.m, Gap.xs),
                      child: Text(
                        aboutMeSections[section]![s.languageCode]!,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    for (final entry in mine)
                      ListTile(
                        title: Text(entry.fact),
                        onTap: () => _edit(context, entry),
                        trailing: IconButton(
                          tooltip: s.delete,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(context, entry.fact, section),
                        ),
                      ),
                  ],
                if (wide)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Gap.m, Gap.m, Gap.m, Gap.xs),
                    child: Align(
                      alignment: entries.isEmpty ? Alignment.center : Alignment.centerLeft,
                      child: add,
                    ),
                  ),
                const Divider(height: Gap.l),
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: Text(s.aboutMeShared(session.aboutMeToCloud)),
                  subtitle: Text(s.aboutMeSharedMeans(session.aboutMeToCloud)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: privacy,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Adds a fact, or changes [old], in the section picked; the store's refusal
/// shows under the field.
class _FactDialog extends StatefulWidget {
  const _FactDialog(this.session, this.old);

  final Session session;
  final ({String section, String fact})? old;

  @override
  State<_FactDialog> createState() => _FactDialogState();
}

class _FactDialogState extends State<_FactDialog> {
  late final _text = TextEditingController(text: widget.old?.fact);
  late var _section = widget.old?.section ?? 'other';
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final session = widget.session;
    final fact = _text.text.trim();
    final old = widget.old?.fact;
    if (old != null && !session.aboutMeFacts().contains(old)) {
      return setState(() => _error = session.strings.factChanged);
    }
    try {
      old == null
          ? await session.rememberFact(fact, section: _section)
          : await session.updateFact(old, fact, section: _section);
    } on ArgumentError {
      return setState(() => _error = session.strings.factTaken);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session.strings;
    final empty = _text.text.trim().isEmpty;
    return AlertDialog(
      title: Text(widget.old == null ? s.addFact : s.editFact),
      content: SizedBox(
        width: Layout.bubble(MediaQuery.sizeOf(context).width),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('fact-field'),
                controller: _text,
                autofocus: true,
                // Wraps to show a long fact, yet Enter saves: one fact stays one line.
                minLines: 1,
                maxLines: 6,
                keyboardType: TextInputType.text,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: empty ? null : (_) => _save(),
                decoration: InputDecoration(labelText: s.fact, errorText: _error),
              ),
              const SizedBox(height: Gap.m),
              Text(s.factSection, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: Gap.s),
              Wrap(
                spacing: Gap.s,
                runSpacing: Gap.s,
                children: [
                  for (final MapEntry(:key, :value) in aboutMeSections.entries)
                    ChoiceChip(
                      label: Text(value[s.languageCode]!),
                      selected: _section == key,
                      onSelected: (_) => setState(() => _section = key),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.cancel)),
        FilledButton(onPressed: empty ? null : _save, child: Text(s.save)),
      ],
    );
  }
}
