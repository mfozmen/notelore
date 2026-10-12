import 'package:flutter/material.dart';

import 'package:notelore_core/notelore_core.dart';

import 'session.dart';
import 'strings.dart';
import 'theme.dart';
import 'update.dart' show appVersion;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen(this.session, {this.checkForUpdates, this.version = appVersion, super.key});

  final Session session;

  /// This build's version ([appVersion]); empty in a development build.
  final String version;

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
      // Grouped in cards; a readable width on wide windows.
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.m, Gap.l),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: Gap.m),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.auto_awesome_outlined),
                        title: Text(s.provider),
                        subtitle: Text(
                          '${s.providerName(session.spec!)} · ${s.groupHeading(session.spec!.group)}',
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Gap.m),
                        child: Row(
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
                                  for (final m in session.models)
                                    DropdownMenuEntry(value: m, label: m),
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
                      ),
                      const SizedBox(height: Gap.s),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Gap.m),
                        child: OutlinedButton(onPressed: _saveModel, child: Text(s.saveModel)),
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.travel_explore),
                        title: Text(s.webSearch),
                        subtitle: Text(
                          !session.spec!.webSearch
                              ? s.webSearchUnavailable
                              : session.spec!.name == 'anthropic'
                              ? s.webSearchBilled
                              : s.webSearchExplained,
                        ),
                        value: session.webSearch && session.spec!.webSearch,
                        onChanged: session.spec!.webSearch ? session.setWebSearch : null,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Gap.m),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.translate),
                  title: Text(s.language),
                  trailing: DropdownButton<AppLanguage>(
                    key: const Key('language'),
                    value: session.language,
                    underline: const SizedBox.shrink(),
                    onChanged: (chosen) => session.setLanguage(chosen!),
                    items: [
                      for (final language in AppLanguage.values)
                        DropdownMenuItem(value: language, child: Text(s.languageName(language))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Gap.m),
              Card(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: Gap.m),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.palette_outlined),
                        title: Text(s.theme),
                        subtitle: Text(s.paletteName(session.palette)),
                      ),
                      // A swatch per landscape; the chosen one is ringed.
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Gap.m),
                        child: Wrap(
                          spacing: Gap.s,
                          runSpacing: Gap.s,
                          children: [
                            for (final palette in Palette.values)
                              _Swatch(
                                palette,
                                label: s.paletteName(palette),
                                chosen: palette == session.palette,
                                onTap: () => session.setPalette(palette),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: Gap.m),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Gap.m),
                        child: SegmentedButton<Appearance>(
                          segments: [
                            for (final a in Appearance.values)
                              ButtonSegment(
                                value: a,
                                label: Text(s.appearanceName(a)),
                                icon: Icon(switch (a) {
                                  Appearance.system => Icons.brightness_auto_outlined,
                                  Appearance.light => Icons.light_mode_outlined,
                                  Appearance.dark => Icons.dark_mode_outlined,
                                }),
                              ),
                          ],
                          selected: {session.appearance},
                          showSelectedIcon: false,
                          onSelectionChanged: (chosen) => session.setAppearance(chosen.single),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Gap.m),
              Card(child: _DriveSection(session)),
              const SizedBox(height: Gap.m),
              Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(s.notesFolder),
                      subtitle: SelectableText(session.paths.notes.path),
                    ),
                    if (widget.checkForUpdates case final check?)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(Gap.m, 0, Gap.m, Gap.m),
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.system_update_alt),
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
                          label: Text(s.checkForUpdates),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.l),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.logout),
                  onPressed: session.logout,
                  label: Text(s.logOut),
                ),
              ),
              const SizedBox(height: Gap.s),
              Text(s.logOutExplained, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: Gap.l),
              Center(
                child: Text(
                  s.versionLine(widget.version),
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
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
        leading: const Icon(Icons.cloud_off_outlined),
        title: Text(session.strings.drive),
        subtitle: Text(session.strings.driveNotSetUp),
      );
    }
    if (!session.driveConnected) {
      return ListTile(
        leading: const Icon(Icons.cloud_outlined),
        title: Text(session.strings.drive),
        subtitle: Text(session.syncStatus ?? session.strings.driveExplained),
        trailing: FilledButton(
          onPressed: () => _connect(context),
          child: Text(session.strings.connect),
        ),
      );
    }
    return ListTile(
      leading: const Icon(Icons.cloud_done_outlined),
      title: Text(session.strings.drive),
      subtitle: Text(
        session.syncing ? session.strings.syncing : session.syncStatus ?? session.strings.connected,
      ),
      trailing: Wrap(
        spacing: Gap.xs,
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

/// One palette as a round swatch of its light and dark colours.
class _Swatch extends StatelessWidget {
  const _Swatch(this.palette, {required this.label, required this.chosen, required this.onTap});

  final Palette palette;
  final String label;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final light = noteloreTheme(Brightness.light, palette).colorScheme;
    final dark = noteloreTheme(Brightness.dark, palette).colorScheme;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: chosen,
        label: label,
        child: InkResponse(
          onTap: onTap,
          radius: 28,
          child: Container(
            width: 48,
            height: 48,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: chosen ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                width: 2,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  stops: const [0.5, 0.5],
                  colors: [light.primary, dark.primaryContainer],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
