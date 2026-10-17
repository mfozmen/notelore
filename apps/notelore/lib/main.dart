import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'src/app.dart';
import 'src/drive_auth.dart';
import 'src/session.dart';
import 'src/share_native.dart';
import 'src/update.dart';

void main() => runApp(
  NoteloreApp(
    open: openSession,
    updater: updaterFor(
      system: Platform.operatingSystem,
      version: appVersion,
      executable: Platform.resolvedExecutable,
    ),
  ),
);

/// The session on this device's folders: the notes and the derived state both
/// in the app's own support folder, which the user never has to see (#207).
/// Notes from earlier versions (a visible `~/Notelore` on the desktop, the
/// app's documents on a phone) move there, so there is one copy.
/// `NOTELORE_HOME` overrides both, for development.
Future<Session> openSession({Map<String, String>? environment, bool? mobile}) async {
  final env = environment ?? Platform.environment;
  final phone = mobile ?? (Platform.isAndroid || Platform.isIOS);
  final support = await getApplicationSupportDirectory();
  final paths = NotelorePaths.resolve(
    environment: env,
    currentDirectory: Directory.current,
    defaultNotes: Directory(p.join(support.path, 'notes')),
    defaultState: support,
  );
  if ((env['NOTELORE_HOME'] ?? '').isEmpty) {
    final home = phone
        ? (await getApplicationDocumentsDirectory()).path
        : env['USERPROFILE'] ?? env['HOME'] ?? Directory.current.path;
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp('[:.]'), '-');
    moveNotes(Directory(p.join(home, 'Notelore')), paths.notes, stamp: stamp);
  }
  final keySpace = (env['NOTELORE_HOME'] ?? '').isNotEmpty ? 'notelore-dev' : 'notelore';
  final session = Session(
    paths,
    keySpace: keySpace,
    driveAuth: driveAuthFor(mobile: phone, keys: appKeys, keySpace: keySpace),
    chatGpt: chatGptAuthFor(mobile: phone, keys: appKeys, keySpace: keySpace),
    localModels: !phone,
    systemLanguage: PlatformDispatcher.instance.locale.languageCode,
    timing: keySpace == 'notelore-dev' ? debugPrint : null, // #232: development runs only
  );
  await session.load();
  if (phone && Platform.isAndroid) listenForShares(session); // "Share → Notelore" (#211)
  return session;
}
