part of 'update.dart';

/// What an update does differently on each platform (#655): [Updater] runs the
/// steps every platform shares (the release, its checksum and signature, the
/// download) and hands the rest to one of these. [updaterFor] and the tests
/// pick it by `system` in [Updater._platformFor], the only place that branches.
sealed class _Platform {
  _Platform(this._u);

  final Updater _u;

  String get executable => _u.executable;
  String get current => _u.current;
  String get home => _u.home;
  String get osVersion => _u.osVersion;
  String get publicKey => _u.publicKey;
  Directory get temp => _u.temp;
  Fetch get fetch => _u.fetch;
  Download? get download => _u.download;
  Run get run => _u.run;
  Spawn get spawn => _u.spawn;
  OpenInstaller get openInstaller => _u.openInstaller;
  void Function(String from, String to) get renameDirectory => _u.renameDirectory;
  void Function(int code) get quit => _u.quit;
  String get system => _u.system;

  /// A smaller update than the full package, staged and ready; its version,
  /// or null to download the full package.
  Future<String?> quick(
    String version,
    Map<String, String> assets,
    void Function(UpdateProgress)? onProgress,
  ) async => null;

  /// Puts the verified package [data], the release file [name], in place.
  Future<void> install(String name, List<int> data);

  /// Starts the new version (see [Updater.relaunch]).
  Future<void> relaunch();

  /// Removes what an earlier update left behind; [Updater.cleanup] keeps
  /// what is still held for the next start.
  void cleanup();

  /// See [Updater.handOff]; only macOS has another copy to start.
  Future<bool> handOff() async => false;
}

/// Windows and Android: the package is a setup or an APK the system opens
/// once this app has handed over.
sealed class _Package extends _Platform {
  _Package(super._u);

  /// The downloaded Windows setup or Android APK, opened by [relaunch].
  String? _setup;

  @override
  Future<void> install(String name, List<int> data) async {
    final folder = temp.createTempSync('notelore-update-');
    _setup = (File(p.join(folder.path, name))..writeAsBytesSync(data)).path;
  }

  /// Setups and APKs of earlier updates: they were opened after this app
  /// handed over, so it could not delete them then.
  void _clearDownloads() {
    for (final folder in temp.listSync().whereType<Directory>()) {
      if (p.basename(folder.path).startsWith('notelore-update-') ||
          p.basename(folder.path).startsWith('notelore-delta-')) {
        folder.deleteSync(recursive: true);
      }
    }
  }
}

final class _Windows extends _Package {
  _Windows(super._u);

  /// The app folder, which the setup or the changed files replace.
  String get installed => p.dirname(executable);

  /// The changed-files job and helper, when a delta was staged (#584).
  String? _deltaJob;
  String? _deltaHelper;

  /// Stages a signed changed-files Windows update for [version] if the release
  /// has one and it verifies; null falls back to the full package.
  @override
  Future<String?> quick(
    String version,
    Map<String, String> assets,
    void Function(UpdateProgress)? onProgress,
  ) async {
    if (publicKey.isEmpty) return null;
    final manifestName = deltaName(version, 'windows-x64', current);
    final manifestUrl = assets[manifestName];
    final signatureUrl = assets['$manifestName.sig'];
    if (manifestUrl == null || signatureUrl == null) return null;
    final manifest = await _readDelta(version, manifestUrl, signatureUrl);
    if (manifest == null) return null;
    final archiveUrl = assets[manifest.archive];
    if (archiveUrl == null) return null;
    final staging = await _stageDelta(manifest, archiveUrl, onProgress);
    if (staging == null) return null;
    final helper = File(p.join(installed, 'notelore-updater.exe'));
    if (!helper.existsSync()) {
      staging.deleteSync(recursive: true);
      return null;
    }
    try {
      final job = UpdateJob(
        install: installed,
        staging: staging.path,
        files: manifest.files,
        executable: p.basename(executable),
        parentPid: pid,
      );
      final jobFile = File(p.join(staging.path, 'job.json'))
        ..writeAsStringSync(jsonEncode(job.toJson()));
      _deltaJob = jobFile.path;
      _deltaHelper = helper.path;
      return version;
    } on Object {
      staging.deleteSync(recursive: true);
      _deltaJob = null;
      _deltaHelper = null;
      return null;
    }
  }

  /// The signed manifest for [version], or null when it does not verify.
  Future<DeltaManifest?> _readDelta(String version, String manifestUrl, String signatureUrl) async {
    try {
      final bytes = await fetch(manifestUrl);
      final signature = utf8.decode(await fetch(signatureUrl), allowMalformed: true);
      if (!await signedBy(bytes, signature, publicKey)) return null;
      return DeltaManifest.parse(
        utf8.decode(bytes),
        version: version,
        current: current,
        system: system,
      );
    } on Object {
      return null;
    }
  }

  /// Downloads and verifies the archive into a staging folder, or null.
  Future<Directory?> _stageDelta(
    DeltaManifest manifest,
    String archiveUrl,
    void Function(UpdateProgress)? onProgress,
  ) async {
    Directory? staging;
    var ok = false;
    try {
      onProgress?.call(const UpdateProgress.downloading(0, null));
      final data = await (download ?? (url, {onProgress}) => fetch(url))(
        archiveUrl,
        onProgress: (received, total) =>
            onProgress?.call(UpdateProgress.downloading(received, total)),
      );
      onProgress?.call(const UpdateProgress(UpdatePhase.verifying));
      if (sha256.convert(data).toString() != manifest.archiveSha256) return null;
      staging = temp.createTempSync('notelore-delta-');
      if (!_stageFiles(staging.path, _entries(data), manifest)) return null;
      ok = true;
      return staging;
    } on Object {
      return null;
    } finally {
      if (!ok) staging?.deleteSync(recursive: true);
    }
  }

  Map<String, Uint8List> _entries(List<int> data) {
    final entries = <String, Uint8List>{};
    for (final entry in ZipDecoder().decodeBytes(data)) {
      if (!entry.isFile) continue;
      entries[entry.name] = Uint8List.fromList(entry.content as List<int>);
    }
    return entries;
  }

  /// Writes every new file into [root], rebuilding a patched one from the
  /// installed copy; false on any mismatch or extra entry.
  bool _stageFiles(String root, Map<String, Uint8List> entries, DeltaManifest manifest) {
    if (entries.length != manifest.files.length) return false;
    for (final MapEntry(key: path, value: expected) in manifest.files.entries) {
      final patch = manifest.patches[path];
      final bytes = entries[patch?.patch ?? path];
      if (patch == null) {
        if (bytes == null || sha256.convert(bytes).toString() != expected) return false;
        _write(root, path, bytes);
      } else if (!_stagePatch(root, path, bytes, expected, patch)) {
        return false;
      }
    }
    return true;
  }

  bool _stagePatch(String root, String path, Uint8List? bytes, String expected, UpdatePatch patch) {
    if (bytes == null || sha256.convert(bytes).toString() != patch.patchSha256) return false;
    final old = File(p.joinAll([installed, ...path.split('/')]));
    if (!old.existsSync()) return false;
    try {
      final patched = applyPatch(
        oldBytes: old.readAsBytesSync(),
        patch: bytes,
        oldSha256: patch.oldSha256,
        newSha256: expected,
        newSize: patch.size,
      );
      if (sha256.convert(patched).toString() != expected) return false;
      _write(root, path, patched);
      return true;
    } on Object {
      return false;
    }
  }

  void _write(String root, String path, List<int> bytes) {
    File(p.joinAll([root, ...path.split('/')]))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes);
  }

  /// The setup, silent, for this user; it starts the app when done. A staged
  /// delta goes to its helper instead.
  @override
  Future<void> relaunch() {
    if (_deltaJob != null) return spawn(_deltaHelper!, [_deltaJob!]);
    return switch (_setup) {
      final setup? => spawn(setup, [
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        // No /DIR: the setup installs for this user, where it was before or by
        // default, and moves an all-users copy out of Program Files (#493).
      ]),
      _ => spawn(executable, const []),
    };
  }

  @override
  void cleanup() {
    _clearDownloads();
    for (final file in Directory(installed).listSync(recursive: true).whereType<File>()) {
      if (file.path.endsWith('.old')) file.deleteSync();
    }
  }
}

final class _Android extends _Package {
  _Android(super._u);

  /// The system installer takes over; cancelling it leaves this app running.
  @override
  Future<void> relaunch() async {
    if (!await openInstaller(_setup!)) throw const InstallNotAllowed();
  }

  @override
  void cleanup() => _clearDownloads(); // the APK replaced the app; nothing else is left
}

final class _Mac extends _Platform {
  _Mac(super._u);

  /// The `.app` bundle this app runs from.
  String get installed => p.dirname(p.dirname(p.dirname(executable)));

  String get _userApps => p.join(home, 'Applications');

  /// The bundle as releases name it; every dmg has it (#635).
  static const _bundleName = 'Notelore.app';

  /// The new bundle's binary, which [relaunch] starts.
  String? _restart;

  /// Where [install] left the bundle, renamed or not.
  String? _bundle;

  /// A fresh `.notelore-update` folder next to [bundle], or null if that
  /// folder cannot be written.
  Directory? _stage(String bundle) {
    final staging = Directory(p.join(p.dirname(bundle), '.notelore-update'));
    try {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
      staging.createSync(recursive: true);
      return staging;
    } on FileSystemException {
      return null;
    }
  }

  /// On macOS, starts the copy an update put in ~/Applications and quits, when
  /// this is an older one left where the user cannot delete it (#644). A copy
  /// that is this one by a link, or not intact, is never started.
  @override
  Future<bool> handOff() async {
    if (home.isEmpty) return false;
    final mine = p.join(_userApps, _bundleName);
    final binary = p.join(mine, 'Contents', 'MacOS', 'Notelore');
    try {
      if (Directory(mine).resolveSymbolicLinksSync() ==
              Directory(installed).resolveSymbolicLinksSync() ||
          !File(binary).existsSync()) {
        return false;
      }
      final plist = File(p.join(mine, 'Contents', 'Info.plist')).readAsStringSync();
      final version = RegExp(
        r'<key>CFBundleShortVersionString</key>\s*<string>(\d+(?:\.\d+)*)</string>',
      ).firstMatch(plist)?[1];
      if (version == null || isNewer(current, version)) return false;
    } on FileSystemException {
      return false; // also a binary plist, which is not UTF-8
    }
    try {
      if ((await run('codesign', ['--verify', '--strict', mine])).exitCode != 0) return false;
      await spawn(binary, const []);
    } on ProcessException {
      return false; // this copy opens instead
    }
    quit(0);
    return true;
  }

  /// Puts the macOS bundle from the dmg [data] in place of this one, or in
  /// ~/Applications when a standard account cannot write this one's folder.
  @override
  Future<void> install(String name, List<int> data) async {
    // Staged next to the bundle, so the swap is a rename on the same drive.
    var target = installed;
    var staging = _stage(target);
    if (staging == null && home.isNotEmpty) {
      target = p.join(_userApps, _bundleName);
      staging = _stage(target);
    }
    if (staging == null) {
      throw UpdateFailed(
        'cannot write next to the app (${p.dirname(installed)}): '
        'move Notelore to a folder you own, then update again',
      );
    }
    try {
      final image = File(p.join(staging.path, name))..writeAsBytesSync(data);
      final mount = p.join(staging.path, 'mnt');
      final bundle = p.join(staging.path, 'app', _bundleName);
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
        final copied = await run('ditto', [p.join(mount, _bundleName), bundle]);
        // A half-copied bundle must never replace a working one.
        if (copied.exitCode != 0) throw UpdateFailed('copying the app failed: ${copied.stderr}');
      } finally {
        await run('hdiutil', ['detach', mount, '-force']);
      }
      _runsHere(bundle);
      if (target == installed) {
        _swapBundle(bundle, target, renameDirectory);
        _bundle = _named();
      } else if (Directory(target).existsSync()) {
        _swapBundle(bundle, target, renameDirectory);
        _bundle = target;
      } else {
        renameDirectory(bundle, target);
        _bundle = target;
      }
      _restart = p.join(_bundle!, 'Contents', 'MacOS', 'Notelore');
    } finally {
      staging.deleteSync(recursive: true);
    }
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
      throw const UpdateFailed('the download has no $_bundleName; not installing it');
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

  /// The installed bundle, renamed to [_bundleName] if it is an install from
  /// before #635 ("notelore.app"); a name the user gave it stays.
  String _named() {
    if (p.basename(installed) != 'notelore.app') return installed;
    final named = p.join(p.dirname(installed), _bundleName);
    try {
      renameDirectory(installed, named);
    } on FileSystemException {
      return installed; // the update is in; only its name stays old
    }
    try {
      // [cleanup] looks for the bundle's own name + .old.
      renameDirectory('$installed.old', '$named.old');
    } on FileSystemException {
      // Kept: only on a case-sensitive volume does the old name stay apart.
    }
    return named;
  }

  @override
  Future<void> relaunch() => spawn(_restart ?? executable, const []);

  @override
  void cleanup() {
    final old = Directory('${_bundle ?? installed}.old');
    if (old.existsSync()) old.deleteSync(recursive: true);
  }
}
