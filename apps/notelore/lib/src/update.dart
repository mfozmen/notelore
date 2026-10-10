/// Update check and self-update of the desktop app against GitHub Releases.
///
/// Port of the CLI's updater: at most one check a day (silent when offline),
/// and an update is installed only when its SHA-256 matches the `.sha256`
/// published with the release (this catches corrupt or partial downloads; it is
/// not a signature). On Windows the release's setup runs silently into this
/// app's folder once the app has exited, and starts it again. On macOS the
/// `.app` comes out of the release's dmg (`hdiutil`, then `ditto`, which keeps
/// the bundle's symlinks) and replaces the old bundle, which stays as `.old`
/// until the next start; a failed swap is rolled back.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

const latestReleaseUrl = 'https://api.github.com/repos/mfozmen/notelore/releases/latest';

/// Set by the release build (`--dart-define=NOTELORE_VERSION=x.y.z`); empty in
/// development builds, which never update themselves.
const appVersion = String.fromEnvironment('NOTELORE_VERSION');

typedef Fetch = Future<List<int>> Function(String url);
typedef Run = Future<ProcessResult> Function(String command, List<String> args);
typedef Spawn = Future<void> Function(String executable, List<String> args);

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
/// at most once a day; offline or a garbled answer is silent.
Future<String?> checkForUpdate({
  required File cache,
  required DateTime now,
  required String current,
  required Fetch fetch,
}) async {
  String? version;
  try {
    final saved = jsonDecode(cache.readAsStringSync()) as Map<String, Object?>;
    final checked = DateTime.parse(saved['checked_at']! as String);
    if (now.difference(checked) < const Duration(days: 1)) version = saved['version']! as String;
  } on Object {
    version = null; // no cache yet, or a damaged one: ask again
  }
  if (version == null) {
    try {
      version = (await latestRelease(fetch)).version;
    } on Object {
      return null; // offline or a garbled answer: try again next start
    }
    try {
      cache.parent.createSync(recursive: true);
      cache.writeAsStringSync(
        jsonEncode({'version': version, 'checked_at': now.toUtc().toIso8601String()}),
      );
    } on FileSystemException {
      // a read-only state folder: the check just repeats next start
    }
  }
  return isNewer(version, current) ? version : null;
}

/// The updater for a release build of the desktop app, or null.
Updater? updaterFor({required String system, required String version, required String executable}) {
  if (version.isEmpty || (system != 'windows' && system != 'macos')) return null;
  return Updater(
    system: system,
    executable: executable,
    current: version,
    fetch: httpFetch,
    run: Process.run,
    spawn: startDetached,
  );
}

class Updater {
  Updater({
    required this.system,
    required this.executable,
    required this.current,
    required this.fetch,
    required this.run,
    required this.spawn,
    this.renameDirectory = _renameDirectory,
  });

  /// 'windows' or 'macos'.
  final String system;
  final String executable;
  final String current;
  final Fetch fetch;
  final Run run;
  final Spawn spawn;

  /// Moves a folder; tests make it fail.
  final void Function(String from, String to) renameDirectory;

  /// What gets replaced: the app folder on Windows, the `.app` bundle on macOS.
  String get _installed =>
      system == 'windows' ? p.dirname(executable) : p.dirname(p.dirname(p.dirname(executable)));

  /// The downloaded Windows setup, run by [relaunch].
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
    if (system == 'windows') {
      // The setup replaces the files once this app has exited (see relaunch).
      final folder = Directory.systemTemp.createTempSync('notelore-update-');
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
        await run('ditto', [p.join(mount, 'notelore.app'), bundle]);
      } finally {
        await run('hdiutil', ['detach', mount, '-force']);
      }
      _swapBundle(bundle, _installed, renameDirectory);
    } finally {
      staging.deleteSync(recursive: true);
    }
    return version;
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

  /// Starts the new version; the caller then exits. On Windows that is the
  /// setup, silent, into this app's folder; it starts the app when done.
  Future<void> relaunch() => switch (_setup) {
    final setup? => spawn(setup, [
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/DIR=$_installed',
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
      for (final file in Directory(_installed).listSync(recursive: true).whereType<File>()) {
        if (file.path.endsWith('.old')) file.deleteSync();
      }
    } on FileSystemException {
      // still in use: the next start tries again
    }
  }
}
