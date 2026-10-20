import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import 'package:notelore_core/notelore_core.dart';
import 'package:url_launcher/url_launcher.dart';

import 'lock.dart';
import 'mark.dart';
import 'session.dart';
import 'setup.dart' show ProviderWizard;
import 'strings.dart';
import 'theme.dart';
import 'update.dart' show appVersion;
import 'usage_page.dart';
import 'whisper_speech.dart' show MicrophoneChoice;

/// Settings' categories: the side list on a wide window, the phone's menu.
enum SettingsSection {
  model(Icons.auto_awesome_outlined),
  voice(Icons.record_voice_over_outlined),
  sync(Icons.cloud_outlined),
  appearance(Icons.palette_outlined),
  lock(Icons.lock_outline),
  reminders(Icons.notifications_outlined),
  about(Icons.info_outline);

  const SettingsSection(this.icon);

  final IconData icon;

  String title(Strings s) => switch (this) {
    model => s.model,
    voice => s.voiceSection,
    sync => s.syncSection,
    appearance => s.appearance,
    lock => s.appLock,
    reminders => s.reminders,
    about => s.aboutSection,
  };

  /// The ones this device has: Reminders only where it can notify at all (#431).
  static List<SettingsSection> of(Session session) => [
    for (final section in values)
      if (section != reminders || session.remindersAllowed != null || session.calendarAvailable)
        section,
  ];
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen(
    this.session, {
    this.checkForUpdates,
    this.version = appVersion,
    this.section,
    super.key,
  });

  final Session session;

  /// The one category a phone shows on its own page; null shows them all.
  final SettingsSection? section;

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
    final cards = {
      SettingsSection.model: [_ModelCard(session), _AdvancedCard(session)],
      SettingsSection.voice: [
        _VoiceCard(
          session,
          microphones: _microphones,
          listAgain: () => setState(() {
            _microphones = session.listMicrophones();
          }),
        ),
      ],
      SettingsSection.sync: [Card(child: _DriveSection(session))],
      SettingsSection.appearance: [_LanguageCard(session), _LookCard(session)],
      SettingsSection.lock: [_LockCard(session)],
      SettingsSection.reminders: [_RemindersCard(session)],
      SettingsSection.about: [
        _AboutCard(
          session,
          version: widget.version,
          check: switch (widget.checkForUpdates) {
            final check? when !_checking => () => _checkForUpdates(check),
            _ => null,
          },
          canCheck: widget.checkForUpdates != null,
        ),
      ],
    };
    final sections = SettingsSection.of(session);
    if (widget.section case final section?) {
      return Scaffold(
        appBar: AppBar(title: Text(section.title(s))),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.m, Gap.l),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Layout.column),
                child: _cards(cards[section]!),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(s.settings)),
      body: Builder(
        builder: (context) => Layout.isWide(context)
            // A wide window: the sections on the left, one shown at a time, like
            // a desktop's own settings.
            ? _Sections(
                [for (final section in sections) (section.icon, section.title(s), cards[section]!)],
                shown: _section.clamp(0, sections.length - 1),
                show: (index) => setState(() => _section = index),
              )
            // A narrow window: the same categories as the phone's menu.
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: Gap.s),
                children: [
                  SettingsCategories(
                    session,
                    open: (section) => openSettingsSection(
                      context,
                      session,
                      section,
                      version: widget.version,
                      checkForUpdates: widget.checkForUpdates,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Settings' categories as a list, each opening its own page: the phone's
/// menu and a narrow Settings screen. ListTiles, so a long label at a large
/// text size wraps instead of overflowing.
class SettingsCategories extends StatelessWidget {
  const SettingsCategories(this.session, {required this.open, super.key});

  final Session session;
  final ValueChanged<SettingsSection> open;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final section in SettingsSection.of(session))
        ListTile(
          leading: Icon(section.icon),
          title: Text(section.title(session.strings)),
          onTap: () => open(section),
        ),
    ],
  );
}

/// Opens [section] of Settings on its own page, as a phone shows it.
Future<void> openSettingsSection(
  BuildContext context,
  Session session,
  SettingsSection section, {
  String version = appVersion,
  Future<String> Function()? checkForUpdates,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => SettingsScreen(
      session,
      section: section,
      version: version,
      checkForUpdates: checkForUpdates,
    ),
  ),
);

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
    if (!(sure ?? false) || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await session.disconnect(spec);
    } on Object catch (error) {
      debugPrint('removal failed: ${error.runtimeType}'); // never the detail: it may hold a token
      messenger.showSnackBar(SnackBar(content: Text(s.removeFailed)));
    }
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
                    onPressed: _switching != null ? null : () => _remove(spec),
                  ),
                ),
            ],
          ),
        ),
        // OpenAI's guidelines link the plan's usage; here rather than by the composer (#507).
        if (session.spec?.name == 'chatgpt')
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: Text(s.manageUsage),
            subtitle: Text(s.usingChatGptPlan),
            onTap: () =>
                launchUrl(Uri.parse(chatGptUsageUrl), mode: LaunchMode.externalApplication),
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
/// What only advanced users want, behind one switch (#294): usage, on its own page.
class _AdvancedCard extends StatelessWidget {
  const _AdvancedCard(this.session);

  final Session session;

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.tune),
            title: Text(s.showAdvanced),
            subtitle: Text(s.showAdvancedWhy),
            value: session.advanced,
            onChanged: session.setAdvanced,
          ),
          if (session.advanced)
            ListTile(
              key: const Key('open-usage'),
              leading: const Icon(Icons.bar_chart),
              title: Text(s.usage),
              subtitle: Text(s.usageWhat),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => UsagePage(session))),
            ),
        ],
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
            ListTile(
              leading: const Icon(Icons.record_voice_over_outlined),
              title: Text(s.whisper),
              // What it is and how big, before anyone downloads it.
              subtitle: Text(s.whisperWhy((session.whisper.bytes / 1e6).ceil())),
            ),
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
                  s.downloadFailed(problem),
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
              subtitle: Text(session.lock.enabled ? s.appLockOn(session.lock.kind) : s.appLockOff),
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

/// How reminders reach the user (#431): notifications on this device, or,
/// while those are off, why none comes and a way to allow them.
class _RemindersCard extends StatelessWidget {
  const _RemindersCard(this.session);

  final Session session;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.only(bottom: Gap.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [..._status(context), if (session.calendarAvailable) _calendarSwitch(context)],
      ),
    ),
  );

  /// How reminders come now, and what this device may still need for it.
  List<Widget> _status(BuildContext context) {
    final s = session.strings;
    if (session.calendar) {
      final elsewhere = session.calendarHere == false;
      return [
        ListTile(
          // Without the grant here, this device still reminds.
          leading: Icon(
            elsewhere ? Icons.notifications_outlined : Icons.notifications_off_outlined,
          ),
          title: Text(s.reminders),
          subtitle: Text(elsewhere ? s.calendarElsewhere : s.remindersInCalendar),
        ),
        if (elsewhere) _action(Icons.login, s.signInCalendar, session.signInCalendar),
      ];
    }
    // This device's notifications, where it has them at all.
    final allowed = session.remindersAllowed;
    if (allowed == null) return const [];
    return [
      ListTile(
        leading: Icon(allowed ? Icons.notifications_outlined : Icons.notifications_off_outlined),
        title: Text(s.reminders),
        subtitle: Text(allowed ? s.remindersOn : s.remindersOff),
      ),
      if (!allowed)
        _action(Icons.notifications_active_outlined, s.allowNotifications, () async {
          final messenger = ScaffoldMessenger.of(context);
          // Refused before, the system asks no more: say where to turn them on.
          if (!await session.allowReminders()) {
            messenger.showSnackBar(SnackBar(content: Text(s.notificationsBlocked)));
          }
        }),
    ];
  }

  Widget _action(IconData icon, String label, VoidCallback onPressed) => Padding(
    padding: const EdgeInsets.fromLTRB(Gap.m, 0, Gap.m, Gap.s),
    child: FilledButton.tonalIcon(icon: Icon(icon), onPressed: onPressed, label: Text(label)),
  );

  Widget _calendarSwitch(BuildContext context) {
    final s = session.strings;
    final problem = session.calendarProblem;
    return SwitchListTile(
      // Busy while the sign-in runs: a second tap waits.
      secondary: session.calendarBusy
          ? const SizedBox.square(
              dimension: 24,
              child: Padding(
                padding: EdgeInsets.all(2),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : const Icon(Icons.calendar_month_outlined),
      title: Text(s.addToCalendar),
      // What went wrong stands under the switch it belongs to.
      subtitle: problem == null
          ? Text(s.addToCalendarHint)
          : Text(switch (problem) {
              CalendarProblem.signIn => s.calendarSignInFailed,
              CalendarProblem.update => s.calendarUpdateFailed,
              CalendarProblem.revoked => s.calendarRevoked,
            }, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      value: session.calendar,
      onChanged: session.calendarBusy ? null : session.setCalendar,
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
                onPressed: () {
                  // Setup takes over: a phone's Settings page must not stay on top.
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  session.logout();
                },
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
      if (kDebugMode) debugPrint('Google sign-in failed: $error');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(session.strings.signInFailedWhy(error))));
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
            onPressed: () {
              // The Google step takes over: a phone's Settings page must not stay on top.
              Navigator.of(context).popUntil((route) => route.isFirst);
              session.disconnectDrive();
            },
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
