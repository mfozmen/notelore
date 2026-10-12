import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'chat.dart';
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

class _NoteloreAppState extends State<NoteloreApp> {
  late final Future<Session> _session = widget.open()
    ..then<void>(_adopt, onError: (Object _) {}); // the error shows below
  Session? _opened;

  /// A session that finishes opening after the app is gone is closed at once.
  void _adopt(Session session) => mounted ? _opened = session : session.dispose();

  @override
  void dispose() {
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
    if (state == AppLifecycleState.resumed) widget.session.syncIfIdle();
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
    final wide = width >= 840;
    final extended = width >= 1200;
    final destinations = [
      (Icons.chat_bubble_outline, Icons.chat_bubble, s.chat),
      (Icons.description_outlined, Icons.description, s.notes),
      (Icons.settings_outlined, Icons.settings, s.settings),
    ];
    void select(int tab) => setState(() => _tab = tab);
    final labels = Theme.of(context).textTheme.labelLarge!;
    final page = Column(
      children: [
        if (_available case final version?)
          MaterialBanner(
            content: Text(
              _installed
                  ? s.installed(version)
                  : _updateProblem ??
                        (_updating ? s.installing(version) : s.updateAvailable(version)),
            ),
            actions: [
              TextButton(
                onPressed: _updating
                    ? null
                    : () => setState(() {
                        _dismissed = _available;
                        _available = null;
                      }),
                child: Text(s.later),
              ),
              if (!_installed)
                TextButton(
                  onPressed: _updating ? null : _update,
                  child: Text(widget.updater?.system == 'android' ? s.update : s.updateAndRestart),
                ),
            ],
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
                  NavigationRail(
                    extended: extended,
                    minExtendedWidth: 220,
                    // Labels sized for reading at a desk, not a phone's caption.
                    selectedLabelTextStyle: labels.copyWith(fontWeight: FontWeight.w600),
                    unselectedLabelTextStyle: labels.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    labelType: extended ? null : NavigationRailLabelType.all,
                    selectedIndex: _tab,
                    onDestinationSelected: select,
                    leading: extended
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(Gap.s, Gap.m, 0, Gap.m),
                            child: Text('Notelore', style: Theme.of(context).textTheme.titleLarge),
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
