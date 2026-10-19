/// Update check and self-update of the desktop app against GitHub Releases.
///
/// Port of the CLI's updater: a check at every start (silent when offline),
/// and an update is installed only when its SHA-256 matches the `.sha256`
/// published with the release (this catches corrupt or partial downloads; it is
/// not a signature). On Windows the release's setup runs silently into this
/// app's folder once the app has exited, and starts it again. On macOS the
/// `.app` comes out of the release's dmg (`hdiutil`, then `ditto`, which keeps
/// the bundle's symlinks) and replaces the old bundle, which stays as `.old`
/// until the next start; a failed swap is rolled back. On Android the APK goes
/// to the system installer, where the user taps Install (an app outside a store
/// cannot install itself silently).
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

const latestReleaseUrl = 'https://api.github.com/repos/mfozmen/notelore/releases/latest';

/// Set by the release build (`--dart-define=NOTELORE_VERSION=x.y.z`); empty in
/// development builds, which never update themselves.
const appVersion = String.fromEnvironment('NOTELORE_VERSION');

typedef Fetch = Future<List<int>> Function(String url);
typedef Run = Future<ProcessResult> Function(String command, List<String> args);
typedef Spawn = Future<void> Function(String executable, List<String> args);

/// Hands an APK to Android's installer; false when installs from Notelore are
/// not allowed yet (the setting to allow them has been opened instead).
typedef OpenInstaller = Future<bool> Function(String apk);

const _installer = MethodChannel('io.github.mfozmen.notelore/install');

/// The [OpenInstaller] of the app, through MainActivity.
Future<bool> androidInstaller(String apk) async =>
    await _installer.invokeMethod<bool>('install', apk) ?? false;

/// Android: allow installs from Notelore in the setting that just opened, then
/// update again.
class InstallNotAllowed implements Exception {
  const InstallNotAllowed();
}

void _renameDirectory(String from, String to) => Directory(from).renameSync(to);

class UpdateFailed implements Exception {
  const UpdateFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Numeric compare; anything unparsable (a pre-release tag, "dev") is not newer.
bool isNewer(String candidate, String current) {
  List<int>? parts(String version) {
    final numbers = version.split('.').map(int.tryParse).toList();
    return numbers.contains(null) ? null : numbers.cast<int>();
  }

  final (a, b) = (parts(candidate), parts(current));
  if (a == null || b == null) return false;
  for (var i = 0; i < a.length && i < b.length; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return a.length > b.length; // like Python's tuples: 1.0.0 is newer than 1.0
}

/// The release asset for this OS, as release.yml names it.
String assetName(String version, String system) => switch (system) {
  'windows' => 'notelore-app-$version-windows-x64-setup.exe',
  'macos' => 'notelore-app-$version-macos.dmg',
  'android' => 'notelore-app-$version-android.apk',
  _ => throw UpdateFailed('no prebuilt app for $system'),
};

Future<List<int>> httpFetch(String url, {http.Client? client}) async {
  final http.Response response;
  try {
    response = await (client ?? http.Client())
        .get(Uri.parse(url))
        .timeout(const Duration(minutes: 2));
  } on Exception catch (error) {
    throw UpdateFailed('download failed: $error');
  }
  if (response.statusCode != 200) {
    throw UpdateFailed('download failed: HTTP ${response.statusCode} for $url');
  }
  return response.bodyBytes;
}

Future<void> startDetached(String executable, [List<String> args = const []]) =>
    Process.start(executable, args, mode: ProcessStartMode.detached);

/// The latest release's version and its assets as {name: download url}.
Future<({String version, Map<String, String> assets})> latestRelease(Fetch fetch) async {
  final data = jsonDecode(utf8.decode(await fetch(latestReleaseUrl))) as Map<String, Object?>;
  return (
    version: '${data['tag_name']}'.replaceFirst(RegExp('^v'), ''),
    assets: {
      for (final asset in (data['assets']! as List).cast<Map<String, Object?>>())
        '${asset['name']}': '${asset['browser_download_url']}',
    },
  );
}

/// The newest version when it is newer than [current], else null. Asks GitHub
/// every time (each start); offline or a garbled answer is silent unless [force].
Future<String?> checkForUpdate({
  required String current,
  required Fetch fetch,
  required String system,
  bool force = false,
}) async =>
    (await checkRelease(current: current, fetch: fetch, system: system, force: force))?.version;

/// A newer release than [current], with what it brings and its page (#288);
/// null when there is none. Offline or garbled is silent unless [force]. A
/// release without [system]'s file and its `.sha256` is not one yet: its
/// builds are still running, and an update now would find nothing (#476).
Future<({String version, List<String> highlights, String page})?> checkRelease({
  required String current,
  required Fetch fetch,
  required String system,
  bool force = false,
}) async {
  final Map<String, Object?> data;
  try {
    data = jsonDecode(utf8.decode(await fetch(latestReleaseUrl))) as Map<String, Object?>;
  } on Object {
    if (force) rethrow;
    return null; // offline or a garbled answer: try again next start
  }
  final version = '${data['tag_name']}'.replaceFirst(RegExp('^v'), '');
  if (!isNewer(version, current)) return null;
  // Whatever shape the answer has, a check at start never throws.
  final listed = data['assets'] is List ? data['assets']! as List : const <Object?>[];
  final assets = {
    for (final asset in listed.whereType<Map<Object?, Object?>>()) '${asset['name']}',
  };
  final file = assetName(version, system);
  if (!assets.contains(file) || !assets.contains('$file.sha256')) return null;
  return (
    version: version,
    highlights: releaseHighlights(data['body'] as String?),
    page: '${data['html_url'] ?? 'https://github.com/mfozmen/notelore/releases'}',
  );
}

/// What a release brings, from its notes: the first features, then fixes, two
/// at most, each without its links.
List<String> releaseHighlights(String? notes) {
  final sections = <String, List<String>>{};
  String? heading;
  for (final line in (notes ?? '').split('\n')) {
    if (line.startsWith('### ')) {
      heading = line.substring(4).trim();
    } else if (line.startsWith('- ') && heading != null) {
      final text = line.substring(2).replaceFirst(RegExp(r'\s*\(\[.*$'), '').trim();
      if (text.isNotEmpty) (sections[heading] ??= []).add(text);
    }
  }
  return [...?sections['Features'], ...?sections['Bug Fixes']].take(2).toList();
}

/// The updater for a release build of the desktop app, or null.
Updater? updaterFor({required String system, required String version, required String executable}) {
  if (version.isEmpty || !const {'windows', 'macos', 'android'}.contains(system)) return null;
  return Updater(
    system: system,
    executable: executable,
    current: version,
    temp: Directory.systemTemp,
    fetch: httpFetch,
    run: Process.run,
    spawn: startDetached,
    osVersion: Platform.operatingSystemVersion,
  );
}

class Updater {
  Updater({
    required this.system,
    required this.executable,
    required this.current,
    required this.temp,
    required this.fetch,
    required this.run,
    required this.spawn,
    this.renameDirectory = _renameDirectory,
    this.openInstaller = androidInstaller,
    this.osVersion = '',
  });

  /// This machine's OS as the platform says it ("Version 14.5 (Build 23F79)").
  final String osVersion;

  /// 'windows', 'macos' or 'android'.
  final String system;

  /// Android's installer (see [androidInstaller]).
  final OpenInstaller openInstaller;
  final String executable;
  final String current;

  /// Where setups and APKs are downloaded, and what [cleanup] clears of them:
  /// the system's temp folder in the app, a folder of its own in each test,
  /// so a test's cleanup never deletes another test's download (#330).
  final Directory temp;
  final Fetch fetch;
  final Run run;
  final Spawn spawn;

  /// Moves a folder; tests make it fail.
  final void Function(String from, String to) renameDirectory;

  /// What gets replaced: the app folder on Windows, the `.app` bundle on macOS.
  String get _installed =>
      system == 'windows' ? p.dirname(executable) : p.dirname(p.dirname(p.dirname(executable)));

  /// The downloaded Windows setup or Android APK, opened by [relaunch].
  String? _setup;

  /// Downloads the latest release and checks it; on macOS also swaps the bundle
  /// in. Its version, or null when this is current.
  Future<String?> apply() async {
    final (:version, :assets) = await latestRelease(fetch);
    if (!isNewer(version, current)) return null;
    final name = assetName(version, system);
    final url = assets[name];
    if (url == null) throw UpdateFailed('release $version has no $name; download it from GitHub');
    final checksumUrl = assets['$name.sha256'];
    if (checksumUrl == null) {
      throw UpdateFailed('release $version publishes no checksum for $name; not installing it');
    }
    final fields = utf8
        .decode(await fetch(checksumUrl), allowMalformed: true)
        .trim()
        .split(RegExp(r'\s+'));
    if (fields.first.isEmpty) {
      throw UpdateFailed('the checksum for $name is empty; not installing it');
    }
    final data = await fetch(url);
    if (sha256.convert(data).toString() != fields.first.toLowerCase()) {
      throw UpdateFailed('checksum mismatch for $name; the download was not installed');
    }
    if (system == 'windows' || system == 'android') {
      // The setup replaces the files once this app has exited; the APK goes to
      // the system installer (see relaunch).
      final folder = temp.createTempSync('notelore-update-');
      _setup = (File(p.join(folder.path, name))..writeAsBytesSync(data)).path;
      return version;
    }

    // Staged next to the bundle, so the swap is a rename on the same drive.
    final staging = Directory(p.join(p.dirname(_installed), '.notelore-update'));
    try {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
      staging.createSync(recursive: true);
    } on FileSystemException catch (error) {
      throw UpdateFailed(
        'cannot write next to the app (${error.path ?? staging.path}): '
        'move Notelore to a folder you own, then update again',
      );
    }
    try {
      final image = File(p.join(staging.path, name))..writeAsBytesSync(data);
      final mount = p.join(staging.path, 'mnt');
      final bundle = p.join(staging.path, 'app', 'notelore.app');
      final attached = await run('hdiutil', [
        'attach',
        '-nobrowse',
        '-readonly',
        '-mountpoint',
        mount,
        image.path,
      ]);
      if (attached.exitCode != 0) throw UpdateFailed('opening $name failed: ${attached.stderr}');
      try {
        // ditto keeps the bundle's symlinks and permissions.
        final copied = await run('ditto', [p.join(mount, 'notelore.app'), bundle]);
        // A half-copied bundle must never replace a working one.
        if (copied.exitCode != 0) throw UpdateFailed('copying the app failed: ${copied.stderr}');
      } finally {
        await run('hdiutil', ['detach', mount, '-force']);
      }
      _runsHere(bundle);
      _swapBundle(bundle, _installed, renameDirectory);
    } finally {
      staging.deleteSync(recursive: true);
    }
    return version;
  }

  /// A bundle that needs a newer macOS than this one would not start, and the
  /// working app would be left only as `.old` (#328: the floor went 12 → 14).
  void _runsHere(String bundle) {
    final plist = File(p.join(bundle, 'Contents', 'Info.plist'));
    if (!plist.existsSync()) return;
    final needs = RegExp(r'<key>LSMinimumSystemVersion</key>\s*<string>([\d.]+)</string>')
        .firstMatch(plist.readAsStringSync())?[1];
    final here = RegExp(r'\d+(\.\d+)*').firstMatch(osVersion)?[0];
    if (needs != null && here != null && isNewer(needs, here)) {
      throw UpdateFailed('this release needs macOS $needs; this Mac has $here');
    }
  }

  /// Puts the bundle at [from] in place of [to]; the old one is kept as `.old`
  /// and put back if the new one cannot be moved in.
  static void _swapBundle(String from, String to, void Function(String, String) rename) {
    if (!Directory(from).existsSync()) {
      throw const UpdateFailed('the download has no notelore.app; not installing it');
    }
    final old = Directory('$to.old');
    if (old.existsSync()) old.deleteSync(recursive: true);
    rename(to, old.path);
    try {
      rename(from, to);
    } catch (_) {
      rename(old.path, to); // never leave the user without an app
      rethrow;
    }
  }

  /// Starts the new version; the caller then exits, except on Android, where
  /// the installer takes over (and cancelling it leaves this app running). On
  /// Windows that is the setup, silent, for this user; it starts the app when
  /// done. Throws [InstallNotAllowed] on Android until allowed.
  Future<void> relaunch() async {
    if (system == 'android') {
      if (!await openInstaller(_setup!)) throw const InstallNotAllowed();
      return;
    }
    return _start();
  }

  Future<void> _start() => switch (_setup) {
    final setup? => spawn(setup, [
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      // No /DIR: the setup installs for this user, where it was before or by
      // default, and moves an all-users copy out of Program Files (#493).
    ]),
    _ => spawn(executable, const []),
  };

  /// Removes what an earlier update left behind; whatever is still held stays
  /// for the next start.
  void cleanup() {
    try {
      if (system == 'macos') {
        final old = Directory('$_installed.old');
        if (old.existsSync()) old.deleteSync(recursive: true);
        return;
      }
      // Setups and APKs of earlier updates: they were opened after this app
      // handed over, so it could not delete them then.
      for (final folder in temp.listSync().whereType<Directory>()) {
        if (p.basename(folder.path).startsWith('notelore-update-')) {
          folder.deleteSync(recursive: true);
        }
      }
      if (system == 'android') return; // the APK replaced the app; nothing else is left
      for (final file in Directory(_installed).listSync(recursive: true).whereType<File>()) {
        if (file.path.endsWith('.old')) file.deleteSync();
      }
    } on FileSystemException {
      // still in use: the next start tries again
    }
  }
}
