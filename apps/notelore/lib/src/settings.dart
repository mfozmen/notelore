import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:url_launcher/url_launcher.dart';

import 'icons.dart';
import 'lock.dart';
import 'mark.dart';
import 'model_names.dart';
import 'quick_window.dart' show QuickWindow;
import 'section_label.dart';
import 'session.dart';
import 'setup.dart' show ProviderWizard;
import 'soft.dart';
import 'strings.dart';
import 'theme.dart';
import 'update.dart' show appVersion;
import 'usage_page.dart';
import 'whisper_speech.dart' show MicrophoneChoice;

/// Settings' categories: the side list on a wide window, the phone's menu.
enum SettingsSection {
  model(AppIcons.sparkle),
  voice(AppIcons.voice),
  sync(AppIcons.cloud),
  appearance(AppIcons.palette),
  lock(AppIcons.lock),
  privacy(AppIcons.shield),
  reminders(AppIcons.notifications),
  advanced(AppIcons.insights),
  about(AppIcons.info);

  const SettingsSection(this.icon);

  final IconData icon;

  String title(Strings s) => switch (this) {
    model => s.model,
    voice => s.voiceSection,
    sync => s.syncSection,
    appearance => s.appearance,
    lock => s.appLock,
    privacy => s.privacySection,
    reminders => s.reminders,
    advanced => s.advancedSection,
    about => s.aboutSection,
  };

  /// The ones this device has: Reminders only where it can notify at all (#431).
  static List<SettingsSection> of(Session session) => [
    for (final section in values)
      if (section != reminders || session.remindersAllowed != null || session.calendarAvailable)
        section,
  ];
}

/// What a manual update check found: the line to show, and the version to
/// offer when one is ready.
typedef UpdateCheck = ({String message, String? version});

class SettingsScreen extends StatefulWidget {
  const SettingsScreen(
    this.session, {
    this.checkForUpdates,
    this.updateNow,
    this.version = appVersion,
    this.section,
    super.key,
  });

  final Session session;

  /// The one category a phone shows on its own page; null shows them all.
  final SettingsSection? section;

  /// This build's version ([appVersion]); empty in a development build.
  final String version;

  /// Asks for a newer release now and says what came of it; builds that
  /// update themselves only.
  final Future<UpdateCheck> Function()? checkForUpdates;

  /// Starts the update found by [checkForUpdates]; on a phone it leaves this
  /// page so the banner and its progress are visible. Paired with it: without
  /// this, a check reports a version but offers no action.
  final VoidCallback? updateNow;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// Holds what outlives a card: on a wide window only one section is built at a
/// time, so a card's own state would reset on every switch.
class _SettingsScreenState extends State<SettingsScreen> {
  var _checking = false; // one update check at a time
  String? _updateVersion; // a check found one; the card offers it

  /// The section shown on a wide window.
  var _section = 0;

  /// Usage is open in the wide window's pane.
  var _usage = false;

  /// The device's microphones, listed on opening and again on request.
  late var _microphones = widget.session.listMicrophones();

  Future<void> _checkForUpdates(Future<UpdateCheck> Function() check) async {
    setState(() {
      _checking = true;
      _updateVersion = null;
    });
    final result = await check();
    // The page (or the app) may have closed while GitHub answered.
    if (!mounted) return;
    setState(() {
      _checking = false;
      _updateVersion = result.version;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final s = session.strings;
    final cards = {
      SettingsSection.model: [_ModelCard(session)],
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
      SettingsSection.appearance: [
        _LanguageCard(session),
        _LookCard(session),
        _ChatTextCard(session),
      ],
      SettingsSection.lock: [_LockCard(session)],
      SettingsSection.privacy: [_PrivacyCard(session)],
      SettingsSection.reminders: [_RemindersCard(session)],
      SettingsSection.advanced: [
        if (session.quickWindow case final quick?) _QuickShortcutCard(session, quick),
        _AdvancedCard(
          session,
          onOpen: widget.section == null && Layout.isWide(context)
              ? () => setState(() => _usage = true)
              : null,
        ),
        _TestSpaceCard(session),
      ],
      SettingsSection.about: [
        _AboutCard(
          session,
          version: widget.version,
          check: switch (widget.checkForUpdates) {
            final check? when !_checking => () => _checkForUpdates(check),
            _ => null,
          },
          canCheck: widget.checkForUpdates != null,
          update: widget.updateNow,
          updateVersion: _updateVersion,
        ),
      ],
    };
    final sections = SettingsSection.of(session);
    if (widget.section case final section?) {
      return Scaffold(
        appBar: AppBar(leading: softBack(context), title: Text(section.title(s))),
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
                show: (index) => setState(() {
                  _section = index;
                  _usage = false;
                }),
                pane: _usage
                    ? _UsagePane(session: session, close: () => setState(() => _usage = false))
                    : null,
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Column(
      children: [
        for (final section in SettingsSection.of(session))
          _Category(section.icon, section.title(session.strings), onTap: () => open(section)),
      ],
    ),
  );
}

/// One of Settings' categories: muted, or (picked on a wide window) in the
/// accent on a card.
class _Category extends StatelessWidget {
  const _Category(this.icon, this.name, {required this.onTap, this.selected = false});

  final IconData icon;
  final String name;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: selected ? BorderSide(color: colors.outlineVariant) : BorderSide.none,
    );
    return ListTile(
      leading: Icon(icon),
      title: Text(
        name,
        style: TextStyle(fontSize: 14.5, fontWeight: selected ? FontWeight.w600 : null),
      ),
      minTileHeight: 48,
      shape: shape,
      iconColor: colors.onSurfaceVariant,
      textColor: colors.onSurface,
      selectedColor: colors.primary,
      selectedTileColor: colors.surfaceContainerLow,
      selected: selected,
      onTap: onTap,
    );
  }
}

/// Opens [section] of Settings on its own page, as a phone shows it.
Future<void> openSettingsSection(
  BuildContext context,
  Session session,
  SettingsSection section, {
  String version = appVersion,
  Future<UpdateCheck> Function()? checkForUpdates,
  VoidCallback? updateNow,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => SettingsScreen(
      session,
      section: section,
      version: version,
      checkForUpdates: checkForUpdates,
      updateNow: updateNow,
    ),
  ),
);

/// The section list on the left of a wide window and the [shown] section's
/// cards beside it.
class _Sections extends StatelessWidget {
  const _Sections(this.sections, {required this.shown, required this.show, this.pane});

  final List<(IconData, String, List<Widget>)> sections;
  final int shown;
  final ValueChanged<int> show;

  /// A page shown in the pane instead of the section's cards (Usage, #715).
  final Widget? pane;

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
              _Category(icon, name, selected: index == shown, onTap: () => show(index)),
          ],
        ),
      ),
      Expanded(
        child:
            pane ??
            ListView(
              padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.l, Gap.l),
              children: [
                Align(
                  alignment: Alignment.topCenter,
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

/// Usage in the wide Settings pane, with its own way back (#715).
class _UsagePane extends StatelessWidget {
  const _UsagePane({required this.session, required this.close});

  final Session session;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppBar(
        primary: false,
        leading: softBack(context, onPressed: close),
        title: Text(session.strings.usage),
      ),
      Expanded(child: UsageView(session)),
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
              icon: AppIcons.brain,
              title: s.modelInUse,
              control: _ModelPicker(
                session: session,
                value: session.model,
                entries: [
                  for (final m in {...session.models, ?session.model}) (m, readableModel(m)),
                ],
                onSelected: (m) => _pick(context, m),
              ),
            ),
            SoftSwitchTile(
              secondary: const Icon(AppIcons.web),
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

  Future<void> _removeAll() async {
    final s = session.strings;
    final colors = Theme.of(context).colorScheme;
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(s.removeAllModels),
        content: Text(s.removeAllModelsWhy),
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
    // Setup takes over: a phone's Settings page must not stay on top.
    Navigator.of(context).popUntil((route) => route.isFirst);
    await session.logout();
  }

  Future<void> _connectAnother() async {
    await ProviderWizard.open(context, session);
    if (mounted) _reload();
  }

  Widget _connected() {
    final s = session.strings;
    final colors = Theme.of(context).colorScheme;
    return FutureBuilder(
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
                _ when spec == session.spec => SoftRadio(
                  selected: true,
                  semanticLabel: s.nowUsing(s.providerName(spec)),
                ),
                _ => const SoftRadio(selected: false),
              },
              title: Text(s.providerName(spec)),
              subtitle: Text(s.groupHeading(spec.group)),
              selected: spec == session.spec,
              onTap: spec == session.spec || _switching != null ? null : () => _switch(spec),
              trailing: IconButton(
                tooltip: s.remove,
                // A removal never wears the accent colour of the one in use.
                color: colors.onSurfaceVariant,
                icon: const Icon(AppIcons.delete),
                onPressed: _switching != null ? null : () => _remove(spec),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          s.connectedModels,
          strings: s,
          padding: const EdgeInsets.fromLTRB(Gap.m, Gap.m, Gap.m, Gap.s),
        ),
        _connected(),
        // OpenAI's guidelines link the plan's usage; here rather than by the composer (#507).
        if (session.spec?.access == ProviderAccess.signIn)
          TallTile(
            child: ListTile(
              leading: const Icon(AppIcons.openInNew),
              title: Text(s.manageUsage),
              subtitle: Text(s.usingChatGptPlan),
              onTap: () =>
                  launchUrl(Uri.parse(chatGptUsageUrl), mode: LaunchMode.externalApplication),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.m, session.spec == null ? Gap.m : Gap.xs),
          child: OutlinedButton.icon(
            icon: const Icon(AppIcons.add),
            label: Text(s.connectAnother),
            onPressed: _connectAnother,
          ),
        ),
        if (session.spec != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.m, Gap.xs, Gap.m, Gap.m),
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: colors.error),
              icon: const Icon(AppIcons.logout),
              label: Text(s.removeAllModels),
              onPressed: _switching != null ? null : _removeAll,
            ),
          ),
        const Divider(height: Gap.l),
      ],
    );
  }
}

/// What the model calls used (#217): this conversation and this device.
/// What only advanced users want (#294): usage, on its own page (#558).
class _AdvancedCard extends StatelessWidget {
  const _AdvancedCard(this.session, {this.onOpen});

  final Session session;

  /// In a wide Settings pane, open Usage beside the sections (#715).
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    return Card(
      child: TallTile(
        child: ListTile(
          key: const Key('open-usage'),
          leading: const Icon(AppIcons.chart),
          title: Text(s.usage),
          subtitle: Text(s.usageWhat),
          trailing: const Icon(AppIcons.chevronRight),
          onTap:
              onOpen ??
              () =>
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => UsagePage(session))),
        ),
      ),
    );
  }
}

/// The desktop's quick-note shortcut (#800): on or off on this device.
class _QuickShortcutCard extends StatelessWidget {
  const _QuickShortcutCard(this.session, this.quick);

  final Session session;
  final QuickWindow quick;

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: quick, builder: (context, _) => _card());

  Widget _card() {
    final s = session.strings;
    return Card(
      child: SoftSwitchTile(
        secondary: const Icon(AppIcons.command),
        title: Text(s.quickShortcut),
        subtitle: Text(
          [s.quickShortcutInfo(quick.keysLabel), if (quick.taken) s.quickShortcutTaken].join(' '),
        ),
        value: session.quickShortcut,
        onChanged: (on) => session.setQuickShortcut(on: on),
      ),
    );
  }
}

/// The switch between the real notes and the test space (#832), and clearing
/// the test space: its notes move to its own archive, nothing is deleted.
class _TestSpaceCard extends StatelessWidget {
  const _TestSpaceCard(this.session);

  final Session session;

  Future<void> _clear(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await session.clearTestSpace();
    messenger.showSnackBar(SnackBar(content: Text(session.strings.testSpaceCleared)));
  }

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    final switchSpace = session.switchSpace;
    return Card(
      child: Column(
        children: [
          TallTile(
            child: SwitchListTile(
              key: const Key('test-space'),
              secondary: const Icon(Icons.science_outlined),
              title: Text(s.testSpace),
              subtitle: Text(s.testSpaceWhy),
              value: session.testSpace,
              onChanged: switchSpace == null ? null : (on) => switchSpace(on),
            ),
          ),
          if (session.testSpace)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Gap.m, 0, Gap.m, Gap.s),
                child: TextButton.icon(
                  key: const Key('clear-test-space'),
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: Text(s.testSpaceClear),
                  onPressed: () => _clear(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Whether cloud models get the about-me facts (#646); the facts themselves
/// are a page of their own (#669).
class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard(this.session);

  final Session session;

  @override
  Widget build(BuildContext context) => Card(
    child: SoftSwitchTile(
      secondary: const Icon(AppIcons.shield),
      title: Text(session.strings.aboutMeToCloud),
      subtitle: Text(session.strings.aboutMeToCloudWhy),
      value: session.aboutMeToCloud,
      onChanged: session.setAboutMeToCloud,
    ),
  );
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
          icon: AppIcons.translate,
          title: s.appLanguage,
          control: _picker(
            context: context,
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

/// Light, dark, or the device's.
class _LookCard extends StatelessWidget {
  const _LookCard(this.session);

  final Session session;

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    final colors = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NoteloreTokens>()!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.only(bottom: Gap.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(leading: const Icon(AppIcons.contrast), title: Text(s.theme)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.m),
              child: Wrap(
                spacing: Gap.s,
                runSpacing: Gap.xs,
                children: [
                  for (final a in Appearance.values)
                    ChoiceChip(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Radii.chip),
                        side: BorderSide(
                          color: session.appearance == a
                              ? tokens.mineBorder
                              : colors.outlineVariant,
                        ),
                      ),
                      backgroundColor: colors.surfaceContainerLow,
                      selectedColor: colors.primaryContainer,
                      labelStyle: TextStyle(
                        fontSize: 13.5,
                        color: session.appearance == a
                            ? colors.onPrimaryContainer
                            : colors.onSurface,
                        fontWeight: session.appearance == a ? FontWeight.w600 : null,
                      ),
                      label: Text(s.appearanceName(a)),
                      avatar: Icon(switch (a) {
                        Appearance.system => AppIcons.systemMode,
                        Appearance.light => AppIcons.lightMode,
                        Appearance.dark => AppIcons.darkMode,
                      }),
                      showCheckmark: false,
                      selected: session.appearance == a,
                      onSelected: (_) => session.setAppearance(a),
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

/// The chat's text size, in steps, on this device only.
class _ChatTextCard extends StatelessWidget {
  const _ChatTextCard(this.session);

  final Session session;

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    final step = session.chatTextStep;
    final last = Session.chatTextSteps.length - 1;
    return Card(
      child: Padding(
        padding: const EdgeInsets.only(bottom: Gap.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TallTile(
              child: ListTile(
                leading: const Icon(AppIcons.textSize),
                title: Text(s.chatTextSize),
                subtitle: Text(s.chatTextSizeWhy),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.m),
              // Wraps Reset to the next line at large text, rather than overflow.
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: s.textSizeSmaller,
                    icon: const Icon(AppIcons.textSmaller),
                    onPressed: step > 0 ? session.zoomChatOut : null,
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 64),
                    child: Text(
                      '${(session.chatTextScale * 100).round()}%',
                      key: const Key('chat-text-percent'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    tooltip: s.textSizeLarger,
                    icon: const Icon(AppIcons.textBigger),
                    onPressed: step < last ? session.zoomChatIn : null,
                  ),
                  if (step != Session.chatTextDefault)
                    TextButton(onPressed: session.resetChatText, child: Text(s.textSizeReset)),
                ],
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
            TallTile(
              child: ListTile(
                leading: const Icon(AppIcons.voice),
                title: Text(s.whisper),
                subtitle: Text(s.whisperWhy),
              ),
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
                  icon: const Icon(AppIcons.refresh),
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
      icon: AppIcons.mic,
      title: s.microphone,
      control: Row(
        children: [
          Expanded(
            child: _picker<String?>(
              context: context,
              key: const Key('microphone'),
              value: chosen,
              entries: [(null, s.systemMicrophone), for (final m in microphones) (m.id, m.label)],
              onSelected: session.setMicrophone,
            ),
          ),
          // One plugged in since Settings opened.
          IconButton(
            tooltip: s.listMicrophones,
            icon: const Icon(AppIcons.refresh),
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
            TallTile(
              child: ListTile(
                leading: const Icon(AppIcons.lock),
                title: Text(s.protection),
                subtitle: Text(
                  session.lock.enabled ? s.appLockOn(session.lock.kind) : s.appLockOff,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.m),
              child: session.lock.enabled
                  ? OutlinedButton.icon(
                      icon: const Icon(AppIcons.lockOpen),
                      onPressed: () => turnLockOff(context, session),
                      label: Text(s.turnOff),
                    )
                  : OutlinedButton.icon(
                      icon: const Icon(AppIcons.lock),
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

  /// The state row, only when this device still needs something: its own
  /// Google sign-in, or notifications that are blocked (#515).
  List<Widget> _status(BuildContext context) {
    final s = session.strings;
    if (session.calendar) {
      // Set up here already: the switch says enough.
      if (session.calendarHere != false) return const [];
      return [
        TallTile(
          child: ListTile(
            // Without the grant here, this device still reminds.
            leading: const Icon(AppIcons.notifications),
            title: Text(s.howRemindersArrive),
            subtitle: Text(s.calendarElsewhere),
          ),
        ),
        _action(AppIcons.login, s.signInCalendar, session.signInCalendar),
      ];
    }
    // This device's notifications, where it has them at all.
    if (session.remindersAllowed != false) return const [];
    return [
      TallTile(
        child: ListTile(
          leading: const Icon(AppIcons.notificationsOff),
          title: Text(s.howRemindersArrive),
          subtitle: Text(s.remindersOff),
        ),
      ),
      _action(AppIcons.notificationsOn, s.allowNotifications, () async {
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
    child: OutlinedButton.icon(icon: Icon(icon), onPressed: onPressed, label: Text(label)),
  );

  Widget _calendarSwitch(BuildContext context) {
    final s = session.strings;
    final problem = session.calendarProblem;
    return SoftSwitchTile(
      // Busy while the sign-in runs: a second tap waits.
      secondary: session.calendarBusy
          ? const SizedBox.square(
              dimension: 24,
              child: Padding(
                padding: EdgeInsets.all(2),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : const Icon(AppIcons.calendar),
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

/// The version and an update check where the build can update itself.
class _AboutCard extends StatelessWidget {
  const _AboutCard(
    this.session, {
    required this.version,
    required this.check,
    required this.canCheck,
    required this.update,
    required this.updateVersion,
  });

  final Session session;
  final String version;

  /// Null while a check runs.
  final VoidCallback? check;
  final bool canCheck;

  /// Starts the version [updateVersion] a check found.
  final VoidCallback? update;
  final String? updateVersion;

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
              minVerticalPadding: Gap.m,
              leading: const ExcludeSemantics(child: NoteloreMark(size: 40)),
              title: Text(s.versionLine(version)),
            ),
            if (canCheck)
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.m, 0, Gap.m, Gap.m),
                child: OutlinedButton.icon(
                  icon: const Icon(AppIcons.update),
                  onPressed: check,
                  label: Text(s.checkForUpdates),
                ),
              ),
            if (updateVersion case final version? when update != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.m, 0, Gap.m, Gap.m),
                child: FilledButton.icon(
                  icon: const Icon(AppIcons.update),
                  onPressed: update,
                  label: Text('${s.update} $version'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModelPicker extends StatefulWidget {
  const _ModelPicker({
    required this.session,
    required this.value,
    required this.entries,
    required this.onSelected,
  });

  final Session session;
  final String? value;
  final List<(String, String)> entries;
  final ValueChanged<String> onSelected;

  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  late final _controller = _RefreshingMenuController(_refresh);
  var _refreshing = false;
  String? _failure;

  Future<bool> _refresh() async {
    if (_refreshing || !mounted) return false;
    setState(() {
      _refreshing = true;
      _failure = null;
    });
    try {
      await widget.session.refreshModels();
      return mounted;
    } on Object catch (error) {
      if (mounted) setState(() => _failure = '$error');
      return mounted;
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _retry() async {
    await _refresh();
    if (mounted && _failure == null) _controller.show();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session.strings;
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _picker<String?>(
          context: context,
          key: const Key('model'),
          value: widget.value,
          entries: widget.entries,
          menuController: _controller,
          helper: widget.value == null || readableModel(widget.value!) == widget.value
              ? null
              : widget.value,
          onSelected: (model) => widget.onSelected(model!),
        ),
        if (_refreshing)
          Padding(
            padding: const EdgeInsets.only(top: Gap.s),
            child: LinearProgressIndicator(semanticsLabel: s.refreshingModels),
          ),
        if (_failure case final failure?)
          Semantics(
            container: true,
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: Gap.s),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.refreshModelsFailed, style: TextStyle(color: colors.error)),
                  Text(failure, style: TextStyle(color: colors.error)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _retry,
                      icon: const Icon(AppIcons.refresh),
                      label: Text(s.tryAgain),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _RefreshingMenuController extends MenuController {
  _RefreshingMenuController(this._refresh);

  final Future<bool> Function() _refresh;
  var _opening = false;

  @override
  void open({Offset? position}) {
    if (_opening) return;
    _opening = true;
    unawaited(_openAfterRefresh(position));
  }

  Future<void> _openAfterRefresh(Offset? position) async {
    try {
      if (await _refresh()) super.open(position: position);
    } finally {
      _opening = false;
    }
  }

  void show() => super.open();
}

/// A choice from a list, never typed: the one look every picker in Settings has
/// (themed in theme.dart).
Widget _picker<T>({
  MenuController? menuController,

  required BuildContext context,
  required Key key,
  required T value,
  required List<(T, String)> entries,
  required void Function(T) onSelected,
  String? helper,
}) {
  // A text field cannot ellipsize, so fit the closed field's label; the open
  // menu keeps the whole label with its own ellipsis. At 1x the field has room,
  // so the text is left alone rather than cut early.
  final scale = MediaQuery.textScalerOf(context).scale(1);
  final budget = scale <= 1 ? null : (28 / scale).floor().clamp(8, 64);
  String fitted(String label) =>
      budget == null || label.length <= budget ? label : '${label.substring(0, budget - 1)}…';
  final colors = Theme.of(context).colorScheme;
  // The caret on a small tinted disc, as the Soft look's pickers have it.
  Widget caret(IconData icon) => Container(
    width: 32,
    height: 32,
    decoration: BoxDecoration(shape: BoxShape.circle, color: colors.primaryContainer),
    child: Icon(icon, size: 18, color: colors.primary),
  );
  return DropdownMenu<T>(
    key: key,
    menuController: menuController,
    initialSelection: value,
    requestFocusOnTap: false,
    expandedInsets: EdgeInsets.zero,
    trailingIcon: caret(AppIcons.expand),
    selectedTrailingIcon: caret(AppIcons.collapse),
    helperText: helper,
    dropdownMenuEntries: [
      for (final (value, label) in entries)
        DropdownMenuEntry(
          value: value,
          label: fitted(label),
          labelWidget: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
    ],
    onSelected: (chosen) => onSelected(chosen as T),
  );
}

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
                crossAxisAlignment: CrossAxisAlignment.start,
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
      if (index > 0) const SizedBox(height: Gap.s),
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
      return TallTile(
        child: ListTile(
          leading: const Icon(AppIcons.cloudOff),
          title: Text(session.strings.drive),
          subtitle: Text(session.strings.driveNotSetUp),
        ),
      );
    }
    if (!session.driveConnected) {
      return TallTile(
        child: ListTile(
          leading: const Icon(AppIcons.cloud),
          title: Text(session.strings.drive),
          subtitle: Text(session.syncStatus ?? session.strings.driveExplained),
          trailing: FilledButton(
            onPressed: () => _connect(context),
            child: Text(session.strings.connect),
          ),
        ),
      );
    }
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TallTile(
          child: ListTile(
            leading: const Icon(AppIcons.cloudDone),
            title: Text(session.strings.drive),
            subtitle: Text(
              session.syncing
                  ? session.strings.syncing
                  : session.syncStatus ?? session.strings.connected,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.m, 0, Gap.m, Gap.s),
          child: Wrap(
            spacing: Gap.s,
            runSpacing: Gap.xs,
            children: [
              TextButton.icon(
                onPressed: session.syncing ? null : session.syncNow,
                icon: const Icon(AppIcons.sync),
                label: Text(session.strings.syncNow),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: colors.error),
                onPressed: () {
                  // The Google step takes over: a phone's Settings page must not stay on top.
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  session.disconnectDrive();
                },
                icon: const Icon(AppIcons.linkOff),
                label: Text(session.strings.disconnectDrive),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
