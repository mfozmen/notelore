import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'chat.dart';
import 'notes.dart';
import 'session.dart';
import 'settings.dart';
import 'setup.dart';
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

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Notelore',
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    darkTheme: ThemeData(colorSchemeSeed: Colors.indigo, brightness: Brightness.dark),
    home: FutureBuilder(
      future: _session,
      builder: (context, snapshot) => switch (snapshot) {
        AsyncSnapshot(:final Session data) => ListenableBuilder(
          listenable: data,
          builder: (context, _) => data.ready
              ? Home(data, updater: widget.updater, exitApp: widget.exitApp)
              : SetupScreen(data),
        ),
        AsyncSnapshot(:final Object error) => Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Notelore could not open its folders.\n\n$error'),
            ),
          ),
        ),
        _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.startAutoSync();
    if (widget.updater case final updater?) unawaited(_check(updater));
  }

  /// Back in the foreground (a phone app reopened, a desktop window focused):
  /// pick up what other devices changed meanwhile.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(widget.session.syncNow());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.stopAutoSync();
    super.dispose();
  }

  Future<void> _check(Updater updater) async {
    updater.cleanup();
    final newer = await checkForUpdate(
      cache: File(p.join(widget.session.paths.state.path, 'update-check.json')),
      now: DateTime.now(),
      current: updater.current,
      fetch: updater.fetch,
    );
    if (mounted) setState(() => _available = newer);
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
    } on Exception {
      // Installed, but the new version could not be started from here.
      if (mounted) setState(() => _installed = true);
      return;
    }
    widget.exitApp(0);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          if (_available case final version?)
            MaterialBanner(
              content: Text(
                _installed
                    ? 'Notelore $version is installed. Close and reopen Notelore to use it.'
                    : _updateProblem ??
                          (_updating
                              ? 'Installing Notelore $version...'
                              : 'Notelore $version is available.'),
              ),
              actions: [
                TextButton(
                  onPressed: _updating ? null : () => setState(() => _available = null),
                  child: const Text('Later'),
                ),
                if (!_installed)
                  TextButton(
                    onPressed: _updating ? null : _update,
                    child: const Text('Update and restart'),
                  ),
              ],
            ),
          Expanded(
            child: switch (_tab) {
              0 => ChatScreen(widget.session),
              1 => NotesScreen(widget.session),
              _ => SettingsScreen(widget.session),
            },
          ),
        ],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (tab) => setState(() => _tab = tab),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Chat'),
        NavigationDestination(icon: Icon(Icons.description_outlined), label: 'Notes'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
      ],
    ),
  );
}
