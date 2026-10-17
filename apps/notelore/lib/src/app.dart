import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'chat.dart';
import 'lock.dart';
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
    AppLifecycleState.hidden || AppLifecycleState.paused => _opened?.backgrounded(),
    AppLifecycleState.resumed => _opened?.foregrounded(),
    _ => null,
  };

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
          title: 'Notelore',
          theme: noteloreTheme(Brightness.light, snapshot.data?.palette ?? Palette.lagoon),
          darkTheme: noteloreTheme(Brightness.dark, snapshot.data?.palette ?? Palette.lagoon),
          themeMode: snapshot.data?.appearance.mode ?? ThemeMode.system,
          locale: Locale(strings.languageCode),
          supportedLocales: const [Locale('en'), Locale('tr')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: switch (snapshot) {
            // With the app lock on, nothing else shows until it is opened (#224).
            AsyncSnapshot(:final Session data) when data.locked => LockScreen(data),
            AsyncSnapshot(:final Session data) =>
              data.ready
                  ? Home(data, updater: widget.updater, exitApp: widget.exitApp)
                  : SetupScreen(data),
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
  String? _available; // a newer version
  String? _updateProblem;
  var _updating = false;
  var _installed = false; // installed, waiting for a manual restart
  String? _dismissed; // put off with Later: not shown again by the timer
  Timer? _recheck;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
  /// pick up what other devices changed meanwhile.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
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
    widget.session.stopAutoSync();
    _recheck?.cancel();
    super.dispose();
  }

  /// Shows the banner for a newer release; [force] lets a failure through.
  Future<String?> _check(Updater updater, {bool force = false}) async {
    final newer = await checkForUpdate(
      current: updater.current,
      fetch: updater.fetch,
      force: force,
    );
    // An install in progress keeps its banner; a version put off stays put off.
    if (mounted && !_updating && !_installed) {
      setState(() => _available = newer == _dismissed ? null : newer);
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
    });
    try {
      await widget.updater!.apply();
    } on Exception catch (error) {
      if (mounted) setState(() => _updateProblem = '$error');
      return;
    } finally {
      if (mounted) setState(() => _updating = false);
    }
    try {
      await widget.updater!.relaunch();
    } on InstallNotAllowed {
      if (mounted) setState(() => _updateProblem = widget.session.strings.allowInstalls);
      return;
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        if (widget.updater!.system != 'macos') {
          // Windows runs the setup, Android opens the installer: nothing has changed yet.
          _updateProblem = widget.session.strings.setupFailed(error);
        } else {
          _installed = true; // macOS: swapped in, only the restart failed
        }
      });
      return;
    }
    // Android's installer takes over; cancelling it leaves this app running.
    if (widget.updater!.system != 'android') widget.exitApp(0);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session.strings;
    final width = MediaQuery.sizeOf(context).width;
    // A desktop window navigates from a side rail, with its labels when there
    // is room; a phone from the bottom bar.
    final wide = width >= Layout.wide;
    final destinations = [
      (Icons.chat_bubble_outline, Icons.chat_bubble, s.chat),
      (Icons.description_outlined, Icons.description, s.notes),
      (Icons.settings_outlined, Icons.settings, s.settings),
    ];
    void select(int tab) => setState(() => _tab = tab);
    final page = Column(
      children: [
        if (_available case final version?)
          _UpdateBanner(
            s,
            version: version,
            installed: _installed,
            updating: _updating,
            problem: _updateProblem,
            android: widget.updater?.system == 'android',
            later: () => setState(() {
              _dismissed = _available;
              _available = null;
            }),
            update: _update,
          ),
        Expanded(
          child: switch (_tab) {
            0 => ChatScreen(widget.session),
            1 => NotesScreen(widget.session),
            _ => SettingsScreen(
              widget.session,
              checkForUpdates: widget.updater == null ? null : _checkNow,
            ),
          },
        ),
      ],
    );
    return Scaffold(
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  _SideRail(
                    destinations,
                    selected: _tab,
                    select: select,
                    extended: width >= Layout.roomy,
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: page),
                ],
              )
            : page,
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: select,
              destinations: [
                for (final (icon, chosen, label) in destinations)
                  NavigationDestination(icon: Icon(icon), selectedIcon: Icon(chosen), label: label),
              ],
            ),
    );
  }
}

/// A newer release: install it, or put it off with Later. While it installs
/// both wait; once installed (macOS, when the restart failed) only Later stays.
class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner(
    this.strings, {
    required this.version,
    required this.installed,
    required this.updating,
    required this.problem,
    required this.android,
    required this.later,
    required this.update,
  });

  final Strings strings;
  final String version;
  final bool installed;
  final bool updating;
  final String? problem;
  final bool android;
  final VoidCallback later;
  final VoidCallback update;

  @override
  Widget build(BuildContext context) {
    final s = strings;
    final message = switch (problem) {
      _ when installed => s.installed(version),
      final problem? => problem,
      _ when updating => s.installing(version),
      _ => s.updateAvailable(version),
    };
    return MaterialBanner(
      content: Text(message),
      actions: [
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
