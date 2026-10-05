import 'package:flutter/material.dart';

import 'chat.dart';
import 'notes.dart';
import 'session.dart';
import 'settings.dart';
import 'setup.dart';

/// Opens the session (folders, index, saved provider), then shows setup until a
/// provider is connected and the three tabs after that.
class NoteloreApp extends StatefulWidget {
  const NoteloreApp({required this.open, super.key});

  final Future<Session> Function() open;

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
          builder: (context, _) => data.ready ? Home(data) : SetupScreen(data),
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
  const Home(this.session, {super.key});

  final Session session;

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  var _tab = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: switch (_tab) {
        0 => ChatScreen(widget.session),
        1 => NotesScreen(widget.session),
        _ => SettingsScreen(widget.session),
      },
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
