import 'package:flutter/material.dart';

import 'package:notelore_core/notelore_core.dart';

import 'lock.dart';
import 'mark.dart';
import 'session.dart';
import 'setup.dart' show ProviderWizard;
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
    final usage = _UsageCard(session);
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
                  (Icons.auto_awesome_outlined, s.model, [model, usage]),
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
                      child: _cards([model, language, look, drive, voice, lock, usage, about]),
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
    final spec = session.spec;
    // No model in use (#363): only the list and the way to connect one.
    if (spec == null) return Card(child: _Connections(session));
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
            _Connections(session),
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

/// Every model this device has connected (#362): the one in use marked, any
/// other one tap away, each removable, and the wizard for another.
class _Connections extends StatefulWidget {
  const _Connections(this.session);

  final Session session;

  @override
  State<_Connections> createState() => _ConnectionsState();
}

class _ConnectionsState extends State<_Connections> {
  /// Asked once, and again after a removal or the wizard: never on every
  /// rebuild, so the list does not flicker.
  late Future<List<ProviderSpec>> _connections = widget.session.connections();

  /// The model being switched to while its key is checked again.
  ProviderSpec? _switching;

  Session get session => widget.session;

  void _reload() => setState(() {
    _connections = session.connections();
  });

  Future<void> _switch(ProviderSpec spec) async {
    final s = session.strings;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    setState(() => _switching = spec);
    try {
      await session.switchTo(spec);
      messenger.showSnackBar(SnackBar(content: Text(s.nowUsing(s.providerName(spec)))));
    } on Object catch (error) {
      // A key lost since the list showed it is a StateError: said plainly too.
      messenger.showSnackBar(SnackBar(content: Text(_why(s, error))));
    }
    if (mounted) setState(() => _switching = null);
  }

  static String _why(Strings s, Object error) => switch (error) {
    KeyValidationError(:final message) => message,
    TransientValidationError(:final message) => '$message ${s.checkConnection}',
    _ => s.signInProblem(error),
  };

  Future<void> _remove(ProviderSpec spec) async {
    final s = session.strings;
    final colors = Theme.of(context).colorScheme;
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(s.removeModel(s.providerName(spec))),
        content: Text(s.removeModelWhy),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(s.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
            ),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(s.remove),
          ),
        ],
      ),
    );
    if (!(sure ?? false)) return;
    await session.disconnect(spec);
    if (mounted) _reload();
  }

  Future<void> _connectAnother() async {
    await ProviderWizard.open(context, session);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.m, Gap.m, Gap.m, Gap.s),
          child: Text(
            s.connectedModels,
            style: theme.textTheme.titleSmall?.copyWith(color: colors.primary),
          ),
        ),
        FutureBuilder(
          future: _connections,
          builder: (context, snapshot) => Column(
            children: [
              // The one in use shows at once, before the keystore answers.
              for (final spec in snapshot.data ?? [?session.spec])
                ListTile(
                  key: ValueKey('connection-${spec.name}'),
                  // The one in use is marked; any other is one tap away.
                  leading: switch (spec) {
                    _ when spec == _switching => const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    _ when spec == session.spec => Icon(
                      Icons.check_circle,
                      color: colors.primary,
                      semanticLabel: s.nowUsing(s.providerName(spec)),
                    ),
                    _ => const Icon(Icons.radio_button_unchecked),
                  },
                  title: Text(s.providerName(spec)),
                  subtitle: Text(s.groupHeading(spec.group)),
                  selected: spec == session.spec,
                  onTap: spec == session.spec || _switching != null ? null : () => _switch(spec),
                  trailing: IconButton(
                    tooltip: s.remove,
                    // A removal never wears the accent colour of the one in use.
                    color: colors.onSurfaceVariant,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _remove(spec),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.m, Gap.xs, Gap.m, Gap.m),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: Text(s.connectAnother),
            onPressed: _connectAnother,
          ),
        ),
        const Divider(height: Gap.l),
      ],
    );
  }
}

/// What the model calls used (#217): this conversation and this device.
class _UsageCard extends StatelessWidget {
  const _UsageCard(this.session);

  final Session session;

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    final small = Theme.of(context).textTheme.bodySmall;
    final device = session.usage.device;
    return Card(
      child: Padding(
        padding: const EdgeInsets.only(bottom: Gap.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(leading: const Icon(Icons.data_usage), title: Text(s.usage)),
            for (final (title, summary) in [
              (s.usageConversation, session.usage.conversation),
              (s.usageDevice, device),
            ])
              ListTile(
                title: Text(title),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final line in s.usageLines(summary)) Text(line)],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Gap.s,
                children: [
                  if (device.plan || session.spec?.name == 'chatgpt')
                    Text(s.usagePlan, style: small),
                  if (session.spec?.name == 'ollama') Text(s.usageLocal, style: small),
                  Text(s.usageEstimate(pricesTaken), style: small),
                ],
              ),
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
              subtitle: Text(session.lock.enabled ? s.appLockOn : s.appLockOff),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.m),
              child: session.lock.enabled
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
            ListTile(leading: const NoteloreMark(size: 40), title: Text(s.versionLine(version))),
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
