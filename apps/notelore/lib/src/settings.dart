import 'package:flutter/material.dart';

import 'package:notelore_core/notelore_core.dart';

import 'lock.dart';
import 'session.dart';
import 'strings.dart';
import 'theme.dart';
import 'update.dart' show appVersion;
import 'whisper_speech.dart' show MicrophoneChoice;

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

/// Holds what outlives a card: on a wide window only one section is built at a
/// time, so a card's own state would reset on every switch.
class _SettingsScreenState extends State<SettingsScreen> {
  var _checking = false; // one update check at a time

  /// The section shown on a wide window.
  var _section = 0;

  /// The device's microphones, listed on opening and again on request.
  late var _microphones = widget.session.listMicrophones();

  Future<void> _checkForUpdates(Future<String> Function() check) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _checking = true);
    final result = await check();
    if (mounted) setState(() => _checking = false);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(result)));
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final s = session.strings;
    final model = _ModelCard(session);
    final language = _LanguageCard(session);
    final look = _LookCard(session);
    final drive = Card(child: _DriveSection(session));
    final voice = _VoiceCard(
      session,
      microphones: _microphones,
      listAgain: () => setState(() {
        _microphones = session.listMicrophones();
      }),
    );
    final lock = _LockCard(session);
    final about = _AboutCard(
      session,
      version: widget.version,
      check: switch (widget.checkForUpdates) {
        final check? when !_checking => () => _checkForUpdates(check),
        _ => null,
      },
      canCheck: widget.checkForUpdates != null,
    );
    return Scaffold(
      appBar: AppBar(title: Text(s.settings)),
      // Grouped in cards; a readable width on wide windows.
      body: Builder(
        builder: (context) => Layout.isWide(context)
            // A wide window: the sections on the left, one shown at a time, like
            // a desktop's own settings.
            ? _Sections(
                [
                  (Icons.auto_awesome_outlined, s.model, [model]),
                  (Icons.record_voice_over_outlined, s.voiceSection, [voice]),
                  (Icons.cloud_outlined, s.syncSection, [drive]),
                  (Icons.palette_outlined, s.appearance, [language, look]),
                  (Icons.lock_outline, s.appLock, [lock]),
                  (Icons.info_outline, s.aboutSection, [about]),
                ],
                shown: _section,
                show: (index) => setState(() => _section = index),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.m, Gap.l),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: Layout.column),
                      child: _cards([model, language, look, drive, voice, lock, about]),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// The section list on the left of a wide window and the [shown] section's
/// cards beside it.
class _Sections extends StatelessWidget {
  const _Sections(this.sections, {required this.shown, required this.show});

  final List<(IconData, String, List<Widget>)> sections;
  final int shown;
  final ValueChanged<int> show;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        width: 260,
        child: ListView(
          key: const Key('settings-sections'),
          padding: const EdgeInsets.fromLTRB(Gap.s, Gap.s, Gap.s, Gap.l),
          children: [
            for (final (index, (icon, name, _)) in sections.indexed)
              ListTile(
                leading: Icon(icon),
                title: Text(name),
                selected: index == shown,
                selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
                onTap: () => show(index),
              ),
          ],
        ),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.l, Gap.l),
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Layout.column),
                child: _cards(sections[shown].$3),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

/// The provider, its model and web search.
class _ModelCard extends StatelessWidget {
  const _ModelCard(this.session);

  final Session session;

  Future<void> _pick(BuildContext context, String model) async {
    final messenger = ScaffoldMessenger.of(context);
    await session.setModel(model);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(session.strings.modelSaved)));
  }

  Future<void> _refresh(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await session.refreshModels();
    } on Exception catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    final spec = session.spec!;
    final webSearch = switch (spec) {
      _ when !spec.webSearch => s.webSearchUnavailable,
      _ when spec.name == 'anthropic' => s.webSearchBilled,
      _ => s.webSearchExplained,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.only(bottom: Gap.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: Text(s.provider),
              subtitle: Text('${s.providerName(spec)} · ${s.groupHeading(spec.group)}'),
            ),
            _SettingRow(
              icon: Icons.psychology_outlined,
              title: s.model,
              control: Row(
                children: [
                  Expanded(
                    // The models the key can use, picked from the list.
                    child: _picker(
                      key: const Key('model'),
                      value: session.model,
                      entries: [
                        for (final m in {...session.models, ?session.model}) (m, m),
                      ],
                      onSelected: (String? m) => _pick(context, m!),
                    ),
                  ),
                  IconButton(
                    tooltip: s.refreshModels,
                    icon: const Icon(Icons.refresh),
                    onPressed: () => _refresh(context),
                  ),
                ],
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.travel_explore),
              title: Text(s.webSearch),
              subtitle: Text(webSearch),
              value: session.webSearch && spec.webSearch,
              onChanged: spec.webSearch ? session.setWebSearch : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// The app's language.
class _LanguageCard extends StatelessWidget {
  const _LanguageCard(this.session);

  final Session session;

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.s),
        child: _SettingRow(
          icon: Icons.translate,
          title: s.language,
          control: _picker(
            key: const Key('language'),
            value: session.language,
            entries: [
              for (final language in AppLanguage.values) (language, s.languageName(language)),
            ],
            onSelected: (AppLanguage? chosen) => session.setLanguage(chosen!),
          ),
        ),
      ),
    );
  }
}

/// The theme (a palette per landscape) and light or dark.
class _LookCard extends StatelessWidget {
  const _LookCard(this.session);

  final Session session;

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    return Card(
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
    );
  }
}

/// Whisper: the microphone once it is there, else its download or why it failed.
class _VoiceCard extends StatelessWidget {
  const _VoiceCard(this.session, {required this.microphones, required this.listAgain});

  final Session session;
  final Future<List<MicrophoneChoice>> microphones;
  final VoidCallback listAgain;

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    final progress = session.whisperProgress;
    return Card(
      child: Padding(
        padding: const EdgeInsets.only(bottom: Gap.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(leading: const Icon(Icons.record_voice_over_outlined), title: Text(s.whisper)),
            if (session.whisper.ready)
              FutureBuilder(future: microphones, builder: _microphone)
            else if (progress != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.m),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: Gap.s),
                    Text(s.whisperDownloading((progress * 100).floor())),
                  ],
                ),
              )
            else if (session.whisperProblem case final problem?) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.m, 0, Gap.m, Gap.s),
                child: Text(
                  s.whisperFailed(problem),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.m),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.refresh),
                  onPressed: session.downloadWhisper,
                  label: Text(s.tryAgain),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _microphone(BuildContext context, AsyncSnapshot<List<MicrophoneChoice>> listed) {
    final s = session.strings;
    final microphones = listed.data ?? const [];
    // A microphone unplugged since it was picked: the default.
    final chosen = microphones.any((m) => m.id == session.microphone) ? session.microphone : null;
    return _SettingRow(
      icon: Icons.mic_none,
      title: s.microphone,
      control: Row(
        children: [
          Expanded(
            child: _picker<String?>(
              key: const Key('microphone'),
              value: chosen,
              entries: [(null, s.systemMicrophone), for (final m in microphones) (m.id, m.label)],
              onSelected: session.setMicrophone,
            ),
          ),
          // One plugged in since Settings opened.
          IconButton(
            tooltip: s.listMicrophones,
            icon: const Icon(Icons.refresh),
            onPressed: listAgain,
          ),
        ],
      ),
    );
  }
}

/// The app lock: on or off.
class _LockCard extends StatelessWidget {
  const _LockCard(this.session);

  final Session session;

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    return Card(
      child: Padding(
        padding: const EdgeInsets.only(bottom: Gap.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(s.appLock),
              subtitle: Text(session.lockEnabled ? s.appLockOn : s.appLockOff),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.m),
              child: session.lockEnabled
                  ? OutlinedButton.icon(
                      icon: const Icon(Icons.lock_open_outlined),
                      onPressed: () => turnLockOff(context, session),
                      label: Text(s.turnOff),
                    )
                  : FilledButton.tonalIcon(
                      icon: const Icon(Icons.lock_outline),
                      onPressed: () => turnLockOn(context, session),
                      label: Text(s.turnOn),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The version, an update check where the build can update itself, and log out.
class _AboutCard extends StatelessWidget {
  const _AboutCard(
    this.session, {
    required this.version,
    required this.check,
    required this.canCheck,
  });

  final Session session;
  final String version;

  /// Null while a check runs.
  final VoidCallback? check;
  final bool canCheck;

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    return Card(
      child: Padding(
        padding: const EdgeInsets.only(bottom: Gap.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(leading: const Icon(Icons.info_outline), title: Text(s.versionLine(version))),
            if (canCheck)
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.m, 0, Gap.m, Gap.m),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.system_update_alt),
                  onPressed: check,
                  label: Text(s.checkForUpdates),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.m),
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.logout),
                onPressed: session.logout,
                label: Text(s.logOut),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.m, 0),
              child: Text(s.logOutExplained, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}

/// A choice from a list, never typed: the one look every picker in Settings has
/// (themed in theme.dart).
Widget _picker<T>({
  required Key key,
  required T value,
  required List<(T, String)> entries,
  required void Function(T) onSelected,
}) => DropdownMenu<T>(
  key: key,
  initialSelection: value,
  requestFocusOnTap: false,
  expandedInsets: EdgeInsets.zero,
  dropdownMenuEntries: [
    for (final (value, label) in entries) DropdownMenuEntry(value: value, label: label),
  ],
  onSelected: (chosen) => onSelected(chosen as T),
);

/// A setting: what it is on the left and its control on the right, or under it
/// where there is no room (a phone).
class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.icon, required this.title, required this.control});

  final IconData icon;
  final String title;
  final Widget control;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final label = ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(title),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.m),
        child: size.maxWidth < 560
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  label,
                  control,
                  const SizedBox(height: Gap.s),
                ],
              )
            : Row(
                children: [
                  Expanded(child: label),
                  const SizedBox(width: Gap.m),
                  SizedBox(width: 320, child: control),
                ],
              ),
      );
    },
  );
}

/// [cards] stacked with the usual gap between them.
Widget _cards(List<Widget> cards) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    for (final (index, card) in cards.indexed) ...[
      if (index > 0) const SizedBox(height: Gap.m),
      card,
    ],
  ],
);

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
