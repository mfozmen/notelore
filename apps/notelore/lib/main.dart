import 'dart:io';

import 'package:flutter/material.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'src/app.dart';
import 'src/session.dart';

void main() => runApp(const NoteloreApp(open: openSession));

/// The session on this device's folders. On the desktop the notes are a visible
/// `~/Notelore` (people open it in other tools); on a phone they live in the
/// app's documents. Derived state goes to the app support folder.
/// `NOTELORE_HOME` overrides both, for development.
Future<Session> openSession({Map<String, String>? environment, bool? mobile}) async {
  final env = environment ?? Platform.environment;
  final phone = mobile ?? (Platform.isAndroid || Platform.isIOS);
  final home = phone
      ? (await getApplicationDocumentsDirectory()).path
      : env['USERPROFILE'] ?? env['HOME'] ?? Directory.current.path;
  final paths = NotelorePaths.resolve(
    environment: env,
    currentDirectory: Directory.current,
    defaultNotes: Directory(p.join(home, 'Notelore')),
    defaultState: await getApplicationSupportDirectory(),
  );
  final dev = (env['NOTELORE_HOME'] ?? '').isNotEmpty;
  final session = Session(paths, keySpace: dev ? 'notelore-dev' : 'notelore');
  await session.load();
  return session;
}
