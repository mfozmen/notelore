import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import 'calendar.dart';
import 'chat.dart';
import 'lock.dart';
import 'mark.dart';
import 'notes.dart';
import 'session.dart';
import 'settings.dart';
import 'setup.dart';
import 'strings.dart';
import 'theme.dart';
import 'update.dart';

/// Opens the session (folders, index, saved provider), then shows setup until a
/// provider is connected and the three tabs after that.
class NoteloreApp extends StatefulWidget {
  const NoteloreApp({required this.open, this.updater, this.exitApp = exit, super.key});

  final Future<Session> Function() open;

  /// Null in development builds and on phones.
  final Updater? updater;
  final void Function(int code) exitApp;

  @override
  State<NoteloreApp> createState() => _NoteloreAppState();
}

class _NoteloreAppState extends State<NoteloreApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// The app lock closes again after a while in the background (#224). Losing
  /// focus alone (inactive) is not the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => switch (state) {
    AppLifecycleState.hidden || AppLifecycleState.paused => _opened?.lock.backgrounded(),
    AppLifecycleState.resumed => _foregrounded(),
    _ => null,
  };

  /// Every screen the app shows, so locking can close what is open on top (#309).
  final _navigator = GlobalKey<NavigatorState>();

  /// Notices, cleared on locking: one can name a note.
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  /// Locked again: a note or dialog left open closes before the next frame, and
  /// a notice from before goes, so only the lock shows; the home underneath is
  /// the lock screen.
  void _foregrounded() {
    final lock = _opened?.lock;
    lock?.foregrounded();
    if (!(lock?.locked ?? false)) return;
    _navigator.currentState?.popUntil((route) => route.isFirst);
    _messenger.currentState?.clearSnackBars();
  }

  late final Future<Session> _session = widget.open()
    ..then<void>(_adopt, onError: (Object _) {}); // the error shows below
  Session? _opened;

  /// A session that finishes opening after the app is gone is closed at once.
  void _adopt(Session session) => mounted ? _opened = session : session.dispose();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // The app owns the session. Closing it closes the index: an open SQLite file
    // cannot be moved or deleted on Windows.
    _opened?.dispose();
    super.dispose();
  }

  // The whole app follows the session's language, so it rebuilds when that changes.
  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _session,
    builder: (context, snapshot) => ListenableBuilder(
      listenable: snapshot.data ?? Listenable.merge(const []),
      builder: (context, _) {
        final strings = snapshot.data?.strings ?? EnglishStrings();
        return MaterialApp(
          navigatorKey: _navigator,
          scaffoldMessengerKey: _messenger,
          title: 'Notelore',
          theme: noteloreTheme(Brightness.light, snapshot.data?.palette ?? Palette.lagoon),
          darkTheme: noteloreTheme(Brightness.dark, snapshot.data?.palette ?? Palette.lagoon),
          themeMode: snapshot.data?.appearance.mode ?? ThemeMode.system,
          locale: Locale(strings.languageCode),
          supportedLocales: const [Locale('en'), Locale('tr')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: switch (snapshot) {
            // With the app lock on, nothing else shows until it is opened (#224).
            AsyncSnapshot(:final Session data) when data.lock.locked => LockScreen(data),
            // A Google account first, then the provider (#208).
            AsyncSnapshot(:final Session data) when data.needsGoogle => GoogleScreen(data),
            AsyncSnapshot(:final Session data) =>
              (data.ready || data.setUpBefore) && !data.finishingSetup
                  ? Home(data, updater: widget.updater, exitApp: widget.exitApp)
                  : ProviderWizard(data),
            AsyncSnapshot(:final Object error) => Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(strings.openFailed(error)),
                ),
              ),
            ),
            _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
          },
        );
      },
    ),
  );
}

class Home extends StatefulWidget {
  const Home(this.session, {this.updater, this.exitApp = exit, super.key});

  final Session session;
  final Updater? updater;
  final void Function(int code) exitApp;

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  var _tab = 0;
  final _scaffold = GlobalKey<ScaffoldState>();
  late int _seenSharedDraft;
  String? _available; // a newer version

  /// What [_available] brings, and its release page (#288).
  var _highlights = const <String>[];
  String? _page;
  String? _updateProblem;
  UpdateProgress? _progress;
  var _updating = false;
  var _installed = false; // installed, waiting for a manual restart
  String? _dismissed; // put off with Later: not shown again by the timer
  var _signInLater = false; // Drive's sign-in banner put off for this run (#479)
  Timer? _recheck;

  @override
  void initState() {
    super.initState();
    _seenSharedDraft = widget.session.sharedDraftVersion;
    WidgetsBinding.instance.addObserver(this);
    widget.session.addListener(_showSharedDraft);
    widget.session.startAutoSync();
    if (widget.session.showPlanWelcome) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _welcomePlan());
    }
    if (widget.updater case final updater?) {
      updater.cleanup();
      unawaited(_check(updater));
      // An app left open still hears of a release, quietly.
      _recheck = Timer.periodic(
        const Duration(hours: 6),
        (_) => _check(updater, force: true).then<void>((_) {}, onError: (Object _) {}),
      );
    }
  }

  void _showSharedDraft() {
    if (_seenSharedDraft == widget.session.sharedDraftVersion) return;
    _seenSharedDraft = widget.session.sharedDraftVersion;
    if (_tab != 0) setState(() => _tab = 0);
  }

  /// OpenAI's first sign-in confirmation for plan usage, shown once per device.
  Future<void> _welcomePlan() async {
    widget.session.showPlanWelcome = false;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.session.strings.usingPlan),
        content: Text(widget.session.strings.planWelcome),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(widget.session.strings.gotIt),
          ),
        ],
      ),
    );
  }

  /// Back in the foreground (a phone app reopened, a desktop window focused):
  /// pick up what other devices changed meanwhile, and notifications the user
  /// turned on or off in the system settings (#431).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.session.refreshReminders(ask: false));
      widget.session
        ..setForeground(true)
        ..syncIfIdle();
    } else if (state case AppLifecycleState.paused || AppLifecycleState.hidden) {
      widget.session.setForeground(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_showSharedDraft);
    widget.session.stopAutoSync();
    _recheck?.cancel();
    super.dispose();
  }

  /// Shows the banner for a newer release; [force] lets a failure through.
  Future<String?> _check(Updater updater, {bool force = false}) async {
    final release = await checkRelease(
      current: updater.current,
      fetch: updater.fetch,
      system: updater.system,
      force: force,
    );
    final newer = release?.version;
    // An install in progress keeps its banner; a version put off stays put off.
    if (mounted && !_updating && !_installed) {
      setState(() {
        _available = newer == _dismissed ? null : newer;
        _highlights = release?.highlights ?? const [];
        _page = release?.page;
      });
    }
    return newer;
  }

  /// Settings' *Check for updates*: what to tell the user.
  Future<String> _checkNow() async {
    try {
      _dismissed = null; // asked by hand: show it even if put off before
      final newer = await _check(widget.updater!, force: true);
      final s = widget.session.strings;
      return newer == null ? s.upToDate : s.updateAvailable(newer);
    } on Object catch (error) {
      return widget.session.strings.checkFailed(error);
    }
  }

  Future<void> _update() async {
    setState(() {
      _updating = true;
      _updateProblem = null;
      _progress = const UpdateProgress(UpdatePhase.checking);
    });
    try {
      final applied = await _applyUpdate();
      if (applied != null) return _failedUpdate(applied);
      final relaunched = await _relaunchUpdate();
      if (relaunched != null) return _failedUpdate(relaunched);
      if (_installed) return; // macOS swapped it in; only the restart failed
      // Android's installer takes over; cancelling it leaves this app running.
      if (widget.updater!.system != 'android') widget.exitApp(0);
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  /// Null when the download and its checksum are in place, else why not.
  Future<String?> _applyUpdate() async {
    try {
      await widget.updater!.apply(
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      return null;
    } on Exception catch (error) {
      return '$error';
    }
  }

  /// Null once the new version is started (or the installer opened), else why not.
  Future<String?> _relaunchUpdate() async {
    try {
      await widget.updater!.relaunch();
      return null;
    } on InstallNotAllowed {
      return widget.session.strings.allowInstalls;
    } on Exception catch (error) {
      if (widget.updater!.system == 'macos') {
        if (mounted) setState(() => _installed = true); // swapped in; the restart failed
        return null;
      }
      // Windows runs the setup, Android opens the installer: nothing has changed yet.
      return widget.session.strings.setupFailed(error);
    }
  }

  void _failedUpdate(String problem) {
    if (!mounted) return;
    setState(() {
      _progress = null;
      _updateProblem = problem;
    });
  }

  Future<String> Function()? get _checkByHand => widget.updater == null ? null : _checkNow;

  /// The screen of [tab].
  Widget _screen(int tab, {required bool wide}) => switch (tab) {
    // Below the menu, to find it.
    0 when !wide => Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(leading: AppMenu.button(context), title: const Text('Notelore')),
        body: ChatScreen(widget.session),
      ),
    ),
    0 => ChatScreen(widget.session),
    1 => NotesScreen(widget.session),
    2 => CalendarScreen(widget.session, toChat: () => setState(() => _tab = 0)),
    _ => SettingsScreen(widget.session, checkForUpdates: _checkByHand),
  };

  @override
  Widget build(BuildContext context) {
    final s = widget.session.strings;
    final width = MediaQuery.sizeOf(context).width;
    // A desktop window navigates from a side rail, with its labels when there
    // is room; a phone from the bottom bar, which keeps to the screens of the
    // task: Settings, secondary, is in the menu at the top (#509).
    final wide = width >= Layout.wide;
    final destinations = [
      (Icons.chat_bubble_outline, Icons.chat_bubble, s.chat),
      (Icons.description_outlined, Icons.description, s.notes),
      (Icons.calendar_month_outlined, Icons.calendar_month, s.calendar),
      if (wide) (Icons.settings_outlined, Icons.settings, s.settings),
    ];
    final tab = _tab < destinations.length ? _tab : 0; // a window made narrow on Settings
    void select(int tab) => setState(() => _tab = tab);
    final page = Column(
      children: [
        if (_available case final version?)
          _UpdateBanner(
            s,
            version: version,
            highlights: _highlights,
            page: _page,
            installed: _installed,
            updating: _updating,
            progress: _progress,
            problem: _updateProblem,
            android: widget.updater?.system == 'android',
            windows: widget.updater?.system == 'windows',
            later: () => setState(() {
              _dismissed = _available;
              _available = null;
            }),
            update: _update,
          ),
        if (widget.session.heldNotes.isNotEmpty) _HeldBanner(widget.session),
        if (widget.session.driveNeedsSignIn && !_signInLater && tab != 3)
          _SignInBanner(widget.session, later: () => setState(() => _signInLater = true)),
        // Settings has its own sign-in: never the same offer twice on one screen.
        if (widget.session.calendarNudge && tab != 3) _CalendarBanner(widget.session),
        Expanded(child: _screen(tab, wide: wide)),
      ],
    );
    return Scaffold(
      key: _scaffold,
      drawer: wide
          ? null
          : _Menu(
              widget.session,
              open: (section) => openSettingsSection(
                context,
                widget.session,
                section,
                checkForUpdates: _checkByHand,
              ),
            ),
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  _SideRail(
                    destinations,
                    selected: tab,
                    select: select,
                    extended: width >= Layout.roomy,
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: page),
                ],
              )
            : AppMenu(open: () => _scaffold.currentState!.openDrawer(), child: page),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: select,
              destinations: [
                for (final (icon, chosen, label) in destinations)
                  NavigationDestination(icon: Icon(icon), selectedIcon: Icon(chosen), label: label),
              ],
            ),
    );
  }
}

/// The phone's menu, opened from a task screen's app bar: Settings' categories.
class AppMenu extends InheritedWidget {
  const AppMenu({required this.open, required super.child, super.key});

  final VoidCallback open;

  /// The app bar's menu button where there is a menu, else null: a wide
  /// window has Settings in its side rail.
  static Widget? button(BuildContext context) {
    final menu = context.dependOnInheritedWidgetOfExactType<AppMenu>();
    if (menu == null) return null;
    return IconButton(
      tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
      icon: const Icon(Icons.menu),
      onPressed: menu.open,
    );
  }

  @override
  bool updateShouldNotify(AppMenu oldWidget) => open != oldWidget.open;
}

class _Menu extends StatelessWidget {
  const _Menu(this.session, {required this.open});

  final Session session;
  final ValueChanged<SettingsSection> open;

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    final theme = Theme.of(context);
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: Gap.s),
          children: [
            // The app's own menu, not a hidden list: its mark and name first.
            ListTile(
              leading: const NoteloreMark(size: 32, badge: false),
              title: Text('Notelore', style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.m, Gap.m, Gap.m, Gap.xs),
              child: Text(
                s.settings,
                style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
              ),
            ),
            SettingsCategories(
              session,
              open: (section) {
                Scaffold.of(context).closeDrawer();
                open(section);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Drive needs a sign-in again (#479): since v0.17.0 its grant must cover the
/// hidden app folder too. Connect asks for it; Later puts it off for this run.
class _SignInBanner extends StatefulWidget {
  const _SignInBanner(this.session, {required this.later});

  final Session session;
  final VoidCallback later;

  @override
  State<_SignInBanner> createState() => _SignInBannerState();
}

class _SignInBannerState extends State<_SignInBanner> {
  var _signingIn = false;
  String? _problem;

  Future<void> _connect() async {
    setState(() {
      _signingIn = true;
      _problem = null;
    });
    try {
      await widget.session.connectDrive();
    } on Exception catch (error) {
      // Refused, cancelled, offline: said plainly, the detail in a debug log only.
      if (kDebugMode) debugPrint('Google sign-in failed: $error');
      if (mounted) setState(() => _problem = widget.session.strings.signInFailedWhy(error));
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session.strings;
    final colors = Theme.of(context).colorScheme;
    return MaterialBanner(
      leading: Icon(Icons.cloud_off_outlined, color: colors.onSecondaryContainer),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Gap.s,
        children: [
          Text(s.driveSignInBanner),
          if (_problem case final problem?)
            Semantics(
              liveRegion: true, // a screen reader hears that it failed
              child: Text(problem, style: TextStyle(color: colors.error)),
            ),
          if (_signingIn) const LinearProgressIndicator(),
        ],
      ),
      actions: [
        TextButton(onPressed: _signingIn ? null : widget.later, child: Text(s.later)),
        TextButton(onPressed: _signingIn ? null : _connect, child: Text(s.connect)),
      ],
    );
  }
}

/// The calendar is on, set up on another device, and a reminder was just made
/// here: until this device signs in it reminds itself, and the sign-in is one
/// tap away. A refusal is said under the words; Later puts it away for good.
class _CalendarBanner extends StatefulWidget {
  const _CalendarBanner(this.session);

  final Session session;

  @override
  State<_CalendarBanner> createState() => _CalendarBannerState();
}

class _CalendarBannerState extends State<_CalendarBanner> {
  var _signingIn = false;

  Future<void> _signIn() async {
    setState(() => _signingIn = true);
    await widget.session.signInCalendar();
    if (mounted) setState(() => _signingIn = false);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final s = session.strings;
    final colors = Theme.of(context).colorScheme;
    return MaterialBanner(
      leading: Icon(Icons.event_available_outlined, color: colors.onSecondaryContainer),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Gap.s,
        children: [
          Text(s.calendarNudge),
          if (session.calendarProblem == CalendarProblem.signIn && !_signingIn)
            Semantics(
              liveRegion: true, // a screen reader hears that it failed
              child: Text(s.calendarSignInFailed, style: TextStyle(color: colors.error)),
            ),
          if (_signingIn) const LinearProgressIndicator(),
        ],
      ),
      actions: [
        TextButton(onPressed: _signingIn ? null : session.calendarNudgeLater, child: Text(s.later)),
        TextButton(onPressed: _signingIn ? null : _signIn, child: Text(s.signIn)),
      ],
    );
  }
}

/// Many notes gone from Google Drive at once (#454): put them back on Drive,
/// or, once confirmed, let them go here too. Both wait while a sync runs.
class _HeldBanner extends StatelessWidget {
  const _HeldBanner(this.session);

  final Session session;

  /// Shown before deleting: the first few, so a partial wipe can be spotted.
  static const _named = 5;

  Future<void> _delete(BuildContext context) async {
    final s = session.strings;
    final held = session.heldTitles;
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        icon: Icon(Icons.delete_outline, color: Theme.of(dialog).colorScheme.error),
        title: Text(s.deleteHeldQuestion(held.length)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Gap.s,
          children: [
            Text(s.deleteHeldExplained(held.length)),
            Text(
              [
                ...held.take(_named),
                if (held.length > _named) s.andMore(held.length - _named),
              ].join('\n'),
              style: Theme.of(dialog).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(dialog).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
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
    if (sure == true) await session.deleteHeld();
  }

  @override
  Widget build(BuildContext context) {
    final s = session.strings;
    final idle = !session.syncing;
    return MaterialBanner(
      leading: Icon(
        Icons.cloud_off_outlined,
        color: Theme.of(context).colorScheme.onSecondaryContainer,
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Gap.s,
        children: [
          Text(s.heldNotes(session.heldNotes.length)),
          // Restore or delete under way: the buttons wait, this says why.
          if (!idle) const LinearProgressIndicator(),
        ],
      ),
      actions: [
        TextButton(onPressed: idle ? () => _delete(context) : null, child: Text(s.deleteHereToo)),
        TextButton(onPressed: idle ? session.restoreHeld : null, child: Text(s.restoreToDrive)),
      ],
    );
  }
}

/// A newer release: install it, or put it off with Later. While it installs
/// both wait; once installed (macOS, when the restart failed) only Later stays.
class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner(
    this.strings, {
    required this.version,
    required this.highlights,
    required this.page,
    required this.installed,
    required this.updating,
    required this.progress,
    required this.problem,
    required this.android,
    required this.windows,
    required this.later,
    required this.update,
  });

  final Strings strings;
  final String version;
  final List<String> highlights;
  final String? page;
  final bool installed;
  final bool updating;
  final UpdateProgress? progress;
  final String? problem;
  final bool android;
  final bool windows;
  final VoidCallback later;
  final VoidCallback update;

  String _message(Strings s) {
    if (installed) return s.installed(version);
    if (problem case final problem?) return problem;
    if (!updating) return s.updateAvailable(version);
    return switch (progress?.phase) {
      UpdatePhase.checking => s.checkingUpdate,
      UpdatePhase.downloading => s.downloadingUpdate(progress!.received, progress!.total),
      UpdatePhase.verifying => s.verifyingUpdate,
      _ => s.installing(version),
    };
  }

  Widget? _progressBar() {
    if (!updating || progress?.phase != UpdatePhase.downloading) return null;
    final total = progress!.total;
    return LinearProgressIndicator(
      value: total == null || total <= 0 ? null : progress!.received / total,
    );
  }

  Widget? _handoff(BuildContext context) {
    if (!updating || progress?.phase != UpdatePhase.installing || !windows) return null;
    return Text(
      strings.windowsUpdateHandoff,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = strings;
    final brings = highlights.isEmpty || installed || updating || problem != null
        ? null
        : highlights.join(' · ');
    return MaterialBanner(
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Gap.xs,
        children: [
          Text(_message(s)),
          ?_progressBar(),
          ?_handoff(context),
          if (brings != null)
            Text(
              brings,
              maxLines: 2, // the rest is one tap away, under What's new
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
        ],
      ),
      actions: [
        if (page case final page? when !installed)
          TextButton(
            onPressed: () => launchUrl(Uri.parse(page), mode: LaunchMode.externalApplication),
            child: Text(s.whatsNew),
          ),
        TextButton(onPressed: updating ? null : later, child: Text(s.later)),
        if (!installed)
          TextButton(
            onPressed: updating ? null : update,
            child: Text(android ? s.update : s.updateAndRestart),
          ),
      ],
    );
  }
}

/// A desktop window's navigation: a rail on the left, with the app's name and
/// the labels beside the icons when [extended].
class _SideRail extends StatelessWidget {
  const _SideRail(
    this.destinations, {
    required this.selected,
    required this.select,
    required this.extended,
  });

  final List<(IconData, IconData, String)> destinations;
  final int selected;
  final ValueChanged<int> select;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels = theme.textTheme.labelLarge!;
    return NavigationRail(
      extended: extended,
      minExtendedWidth: 220,
      // Labels sized for reading at a desk, not a phone's caption.
      selectedLabelTextStyle: labels.copyWith(fontWeight: FontWeight.w600),
      unselectedLabelTextStyle: labels.copyWith(color: theme.colorScheme.onSurfaceVariant),
      labelType: extended ? null : NavigationRailLabelType.all,
      selectedIndex: selected,
      onDestinationSelected: select,
      leading: extended
          ? Padding(
              padding: const EdgeInsets.fromLTRB(Gap.s, Gap.m, 0, Gap.m),
              child: Text('Notelore', style: theme.textTheme.titleLarge),
            )
          : null,
      destinations: [
        for (final (icon, chosen, label) in destinations)
          NavigationRailDestination(
            icon: Icon(icon),
            selectedIcon: Icon(chosen),
            label: Text(label),
          ),
      ],
    );
  }
}
