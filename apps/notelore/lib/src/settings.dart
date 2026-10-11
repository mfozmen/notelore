import 'package:flutter/material.dart';

import 'package:notelore_core/notelore_core.dart';

import 'session.dart';
import 'strings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen(this.session, {this.checkForUpdates, super.key});

  final Session session;

  /// Asks for a newer release now and says what came of it; desktop builds only.
  final Future<String> Function()? checkForUpdates;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _model = TextEditingController(text: widget.session.model);
  var _checking = false; // one update check at a time

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  Future<void> _saveModel() async {
    final messenger = ScaffoldMessenger.of(context);
    await widget.session.setModel(_model.text);
    _model.text = widget.session.model!;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(widget.session.strings.modelSaved)));
  }

  Future<void> _refreshModels() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.session.refreshModels();
    } on Exception catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final s = session.strings;
    return Scaffold(
      appBar: AppBar(title: Text(s.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s.provider),
            subtitle: Text(
              '${s.providerName(session.spec!)} · ${s.groupHeading(session.spec!.group)}',
            ),
          ),
          Row(
            children: [
              Expanded(
                // The models the key can use; a name not in the list can be typed too.
                child: DropdownMenu<String>(
                  key: const Key('model'),
                  controller: _model,
                  expandedInsets: EdgeInsets.zero,
                  requestFocusOnTap: true,
                  label: Text(s.model),
                  helperText: s.modelHelper(session.defaultModel),
                  dropdownMenuEntries: [
                    for (final m in session.models) DropdownMenuEntry(value: m, label: m),
                  ],
                  onSelected: (_) => _saveModel(),
                ),
              ),
              IconButton(
                tooltip: s.refreshModels,
                icon: const Icon(Icons.refresh),
                onPressed: _refreshModels,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(onPressed: _saveModel, child: Text(s.saveModel)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s.language),
            trailing: DropdownButton<AppLanguage>(
              key: const Key('language'),
              value: session.language,
              onChanged: (chosen) => session.setLanguage(chosen!),
              items: [
                for (final language in AppLanguage.values)
                  DropdownMenuItem(value: language, child: Text(s.languageName(language))),
              ],
            ),
          ),
          _DriveSection(session),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s.notesFolder),
            subtitle: SelectableText(session.paths.notes.path),
          ),
          if (widget.checkForUpdates case final check?)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: _checking
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        setState(() => _checking = true);
                        final result = await check();
                        if (mounted) setState(() => _checking = false);
                        messenger
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(content: Text(result)));
                      },
                child: Text(s.checkForUpdates),
              ),
            ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonal(onPressed: session.logout, child: Text(s.logOut)),
          ),
          Text(s.logOutExplained),
        ],
      ),
    );
  }
}

/// Connect, sync now, disconnect; or why there is no sync in this build.
class _DriveSection extends StatelessWidget {
  const _DriveSection(this.session);

  final Session session;

  Future<void> _connect(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await session.connectDrive();
    } on SignInFailed catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!session.driveAvailable) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(session.strings.drive),
        subtitle: Text(session.strings.driveNotSetUp),
      );
    }
    if (!session.driveConnected) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(session.strings.drive),
        subtitle: Text(session.syncStatus ?? session.strings.driveExplained),
        trailing: FilledButton(
          onPressed: () => _connect(context),
          child: Text(session.strings.connect),
        ),
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(session.strings.drive),
      subtitle: Text(
        session.syncing ? session.strings.syncing : session.syncStatus ?? session.strings.connected,
      ),
      trailing: Wrap(
        spacing: 8,
        children: [
          IconButton(
            tooltip: session.strings.syncNow,
            icon: const Icon(Icons.sync),
            onPressed: session.syncing ? null : session.syncNow,
          ),
          IconButton(
            tooltip: session.strings.disconnectDrive,
            icon: const Icon(Icons.link_off),
            onPressed: session.disconnectDrive,
          ),
        ],
      ),
    );
  }
}
