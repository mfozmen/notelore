/// Everything the screens share: the chosen provider and its key, the agent,
/// the conversation, the notes folder and its Google Drive sync.
///
/// Sync runs on start, after every chat turn and on demand. Chat turns and syncs
/// take turns (one queue), so the agent and the sync never write the same file
/// at once. Being offline is normal: the next sync catches up.
///
/// The API key lives in the platform keystore (Android Keystore, Keychain,
/// Windows Credential Manager); the provider and model in `settings.json` in the
/// state folder, which is derived, device-local state like the index.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;

/// Checks a key and returns the chat models it can use.
typedef Validate = Future<List<String>> Function(ProviderSpec spec, String key);
typedef MakeProvider = LlmProvider Function(
  ProviderSpec spec,
  String? key, {
  String? model,
  BearerToken? planToken,
});

/// The models a ChatGPT plan can use.
typedef ListPlanModels = Future<List<String>> Function(BearerToken token);
typedef RemoteFor = Remote Function(DriveAuth auth);

/// The platform keystore. On macOS the login keychain: the data-protection one
/// needs a signed app with a keychain-access-groups entitlement, which debug
/// builds do not have.
const appKeys = FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false));

Remote _driveRemote(DriveAuth auth) => DriveRemote(http.Client(), auth.token);

enum ChatRole { user, assistant, error }

typedef ChatLine = ({ChatRole role, String text});

class Session extends ChangeNotifier {
  Session(
    this.paths, {
    this.validate = validateKey,
    this.makeProvider = createProvider,
    this.today,
    this.keySpace = 'notelore',
    this.keys = appKeys,
    this.driveAuth,
    this.remoteFor = _driveRemote,
    this.chatGpt,
    this.listPlanModels = listChatGptModels,
  }) : index = NoteIndex(p.join(paths.state.path, 'index.sqlite'), paths.notes.path),
       manifest = Manifest(paths.state.path);

  final NotelorePaths paths;
  final Validate validate;
  final MakeProvider makeProvider;

  /// "Sign in with ChatGPT" for the ChatGPT plan provider; null on phones.
  final OAuthSignIn? chatGpt;
  final ListPlanModels listPlanModels;

  /// Set when the ChatGPT plan was connected for the first time on this device:
  /// the screen shows OpenAI's "You're using your ChatGPT plan" once.
  var showPlanWelcome = false;

  /// The providers this device offers.
  List<ProviderSpec> get providers => [
    for (final spec in providerSpecs)
      if (spec.name != 'chatgpt' || chatGpt != null) spec,
  ];

  /// Tests pin it; the app uses the local date.
  final DateTime? today;

  /// Prefix of the keystore entries; a development run uses its own, so it never
  /// reads or overwrites the keys of the real app on the same machine.
  final String keySpace;
  final FlutterSecureStorage keys;
  final NoteIndex index;

  /// Null in a build without Google sign-in (no OAuth client ids).
  final DriveAuth? driveAuth;
  final RemoteFor remoteFor;
  final Manifest manifest;

  ProviderSpec? spec;
  String? model;

  /// The chat models the key can use, as the provider listed them on connect
  /// or refresh; kept in the settings so the list works offline.
  List<String> models = const [];
  Agent? _agent;
  LlmProvider? _provider;
  Remote? _remote;
  var driveConnected = false;
  var _pendingSyncs = 0;

  /// A sync is running or queued.
  bool get syncing => _pendingSyncs > 0;

  /// What the last sync did, for the settings screen; null before any.
  String? syncStatus;

  /// Chat turns and syncs, one after the other.
  Future<void> _queue = Future.value();

  /// Completes when everything queued so far is done.
  Future<void> get syncDone => _queue;

  bool get driveAvailable => driveAuth != null;
  final transcript = <ChatLine>[];
  bool busy = false;

  /// What the running chat turn is doing ("Thinking", "Searching the notes").
  String? step;

  bool get ready => _agent != null;

  String get _settings => p.join(paths.state.path, 'settings.json');

  String _keyName(ProviderSpec spec) => '$keySpace.${spec.name}.api_key';

  /// Picks up the provider chosen on an earlier run, and syncs when Drive is
  /// connected (in the background: an offline start is fine).
  Future<void> load() async {
    await _loadProvider();
    driveConnected = await driveAuth?.signedIn() ?? false;
    notifyListeners();
    if (driveConnected) unawaited(syncNow());
  }

  Future<void> _loadProvider() async {
    final Object? saved;
    try {
      saved = jsonDecode(File(_settings).readAsStringSync());
    } on FileSystemException {
      return; // first run
    } on FormatException {
      return; // damaged: set up again
    }
    if (saved case {'provider': final String name, 'model': final String chosen}) {
      final found = providerSpecs.where((s) => s.name == name).firstOrNull;
      if (found == null) return;
      final key = found.requiresApiKey ? await keys.read(key: _keyName(found)) : '';
      if (key == null) return; // the keystore lost it: set up again
      if (found.name == 'chatgpt' && !(await chatGpt?.signedIn() ?? false)) return;
      models = switch (saved['models']) {
        final List<Object?> listed => listed.whereType<String>().toList(),
        _ => const [], // settings from before the model list
      };
      _use(found, key, chosen);
    }
  }

  /// Checks [key] with the provider, then remembers it. Throws
  /// [KeyValidationError] or [TransientValidationError] and changes nothing.
  /// The key and the settings are saved together: if the settings cannot be
  /// written, the key is taken back out of the keystore.
  Future<void> connect(ProviderSpec spec, String key, {String? model}) async {
    final trimmed = key.trim();
    final listed = await _models(spec, trimmed, signIn: true);
    // A provider without a fixed default (the ChatGPT plan) starts on the first it lists.
    final chosen = model ?? (spec.defaultModel.isNotEmpty ? spec.defaultModel : listed.firstOrNull);
    if (chosen == null) throw TransientValidationError('${spec.displayName} lists no models');
    final name = _keyName(spec);
    final previous = spec.requiresApiKey ? await keys.read(key: name) : null;
    if (spec.requiresApiKey) await keys.write(key: name, value: trimmed);
    try {
      _save(spec, chosen, listed);
    } catch (_) {
      if (spec.requiresApiKey) await _restoreKey(name, previous);
      rethrow;
    }
    models = listed;
    // Set before _use: the home screen it brings up shows the welcome.
    if (spec.name == 'chatgpt' && await keys.read(key: '$keySpace.chatgpt.welcomed') == null) {
      showPlanWelcome = true;
      await keys.write(key: '$keySpace.chatgpt.welcomed', value: 'yes');
    }
    _use(spec, trimmed, chosen);
  }

  /// The models [spec] offers. A key is checked by listing them; the ChatGPT
  /// plan signs in first when [signIn] (only on connect: a refresh never opens
  /// a browser).
  Future<List<String>> _models(ProviderSpec spec, String key, {required bool signIn}) async {
    if (spec.name != 'chatgpt') return validate(spec, key);
    if (signIn) await chatGpt!.signIn();
    return listPlanModels(chatGpt!.token);
  }

  /// Puts back the key that was stored before (none: removes it). Best effort:
  /// the settings error that caused this is the one the caller sees.
  Future<void> _restoreKey(String name, String? previous) async {
    try {
      previous == null
          ? await keys.delete(key: name)
          : await keys.write(key: name, value: previous);
    } on Exception {
      // the keystore failing too must not hide the original error
    }
  }

  /// The provider's default model; for one without a fixed default (the
  /// ChatGPT plan), the first it lists.
  String get defaultModel =>
      spec!.defaultModel.isNotEmpty ? spec!.defaultModel : (models.firstOrNull ?? '');

  /// A blank [chosen] goes back to [defaultModel].
  Future<void> setModel(String chosen) async {
    final current = spec;
    if (current == null) return;
    final key = current.requiresApiKey ? await keys.read(key: _keyName(current)) : '';
    if (key == null) return logout(); // the keystore lost it: set up again
    final trimmed = chosen.trim();
    final next = trimmed.isEmpty ? defaultModel : trimmed;
    _save(current, next, models);
    _use(current, key, next);
  }

  /// Asks the provider again which models the key can use. Throws
  /// [KeyValidationError] or [TransientValidationError] and keeps the old list.
  Future<void> refreshModels() async {
    final current = spec;
    final chosen = model;
    if (current == null || chosen == null) return;
    final key = current.requiresApiKey ? await keys.read(key: _keyName(current)) : '';
    if (key == null) return logout(); // the keystore lost it: set up again
    final listed = await _models(current, key, signIn: false);
    // Logged out or switched provider while the list was on its way: it is stale.
    if (spec != current || model != chosen) return;
    _save(current, chosen, listed);
    models = listed;
    notifyListeners();
  }

  /// Forgets every provider's key on this device and the chosen provider; the
  /// notes stay.
  Future<void> logout() async {
    for (final spec in providerSpecs.where((s) => s.requiresApiKey)) {
      await keys.delete(key: _keyName(spec));
    }
    await chatGpt?.signOut();
    final settings = File(_settings);
    if (settings.existsSync()) settings.deleteSync();
    spec = null;
    model = null;
    models = const [];
    _agent = null;
    _provider = null;
    transcript.clear();
    notifyListeners();
  }

  void _use(ProviderSpec chosen, String key, String chosenModel) {
    spec = chosen;
    model = chosenModel;
    final toolbox = Toolbox(paths.notes.path, index, today: today);
    _provider = makeProvider(
      chosen,
      key,
      model: chosenModel,
      planToken: chosen.name == 'chatgpt' ? chatGpt!.token : null,
    );
    // A model switch keeps the conversation; logout has already dropped it.
    final history = _agent?.messages ?? const <Message>[];
    _agent = Agent(_provider!, toolbox, today: today)..messages.addAll(history);
    notifyListeners();
  }

  void _save(ProviderSpec chosen, String chosenModel, List<String> listed) => atomicWrite(
    _settings,
    '${jsonEncode({'provider': chosen.name, 'model': chosenModel, 'models': listed})}\n',
  );

  Future<T> _exclusive<T>(Future<T> Function() task) {
    final run = _queue.then((_) => task());
    _queue = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  /// One chat turn, then a sync. A provider failure becomes an error line; the
  /// agent has already taken the turn back, so the user can simply send again.
  Future<void> send(String text) async {
    final message = text.trim();
    if (message.isEmpty || busy) return;
    transcript.add((role: ChatRole.user, text: message));
    busy = true;
    _stopped = false;
    notifyListeners();
    await _exclusive(() async {
      try {
        if (_stopped) throw const TurnStopped(); // stopped while queued behind a sync
        final answer = await _agent!.ask(
          message,
          onStep: (now) {
            step = now;
            notifyListeners();
          },
        );
        transcript.add((role: ChatRole.assistant, text: answer));
      } on Exception catch (error) {
        transcript.add((role: ChatRole.error, text: '$error'));
      } finally {
        busy = false;
        step = null;
        notifyListeners();
      }
    });
    if (driveConnected) unawaited(syncNow());
  }

  var _stopped = false;

  /// Ends the chat turn, running or still queued; it shows as "Stopped.".
  void stop() {
    _stopped = true;
    _agent?.stop();
  }

  /// Interactive Google sign-in, then the first sync. Throws [SignInFailed].
  Future<void> connectDrive() async {
    await driveAuth!.signIn();
    driveConnected = true;
    notifyListeners();
    await syncNow();
  }

  Future<void> disconnectDrive() async {
    await driveAuth!.signOut();
    driveConnected = false;
    syncStatus = null;
    notifyListeners();
  }

  Timer? _autoSync;

  /// While the app is open: a sync every [every], so other devices' changes
  /// come in without asking. A tick is skipped while a sync or a chat turn runs.
  void startAutoSync({Duration every = const Duration(minutes: 3)}) {
    _autoSync?.cancel();
    _autoSync = Timer.periodic(every, (_) => syncIfIdle());
  }

  /// A background sync, unless one is already running or queued or a chat
  /// turn is (that turn syncs when it ends).
  void syncIfIdle() {
    if (driveConnected && !syncing && !busy) unawaited(syncNow());
  }

  void stopAutoSync() {
    _autoSync?.cancel();
    _autoSync = null;
  }

  Future<void> syncNow() async {
    if (!driveConnected) return;
    _pendingSyncs++;
    notifyListeners();
    await _exclusive(() async {
      try {
        final resolver = _provider == null ? null : ModelResolver(askProvider(_provider!));
        final report = await sync(
          paths.notes.path,
          manifest,
          _remote ??= remoteFor(driveAuth!),
          resolver?.call ?? _unresolved, // no model connected: conflicts wait
        );
        syncStatus = _describe(report, resolver?.explanations ?? const []);
      } on NotSignedIn catch (error) {
        driveConnected = false;
        syncStatus = '${error.message}; connect again.';
      } on NetworkError {
        syncStatus = 'Offline; your notes will sync when the connection is back.';
      } on HttpError catch (error) {
        syncStatus = 'Google Drive: ${error.message}';
      } on FileSystemException catch (error) {
        // Windows: antivirus or an editor holds a note past the store's retries.
        syncStatus =
            'A note is in use by another program (${error.message}); the next sync retries.';
      } finally {
        _pendingSyncs--;
        notifyListeners();
      }
    });
  }

  static List<String>? _unresolved(Conflict conflict) => null;

  static String _describe(SyncReport report, List<String> explanations) {
    final parts = [
      for (final (count, what) in [
        (report.pushed.length + report.removedRemote.length, 'sent'),
        (report.pulled.length + report.removedLocal.length, 'received'),
        (report.merged.length, 'merged'),
        (report.skipped.length, 'waiting for a conflict to be settled'),
      ])
        if (count > 0) '$count $what',
    ];
    if (parts.isEmpty) return 'Synced; nothing changed.';
    return ['Synced: ${parts.join(', ')}.', ...explanations].join(' ');
  }

  List<NoteInfo> listNotes() => (index..rebuild()).listNotes();

  /// Moves [note] under `_archive/<date>/`: nothing is ever hard-deleted. Returns
  /// where it went, for [restoreNote]; null when a sync or a chat turn already
  /// removed it. Queued, so it never races a sync.
  Future<String?> deleteNote(NoteInfo note) => _exclusive(() async {
    final path = notePath(paths.notes.path, note.kind, note.slug);
    if (!File(path).existsSync()) return null;
    final archived = archiveNote(paths.notes.path, path, today: today);
    notifyListeners();
    return archived;
  });

  /// Undoes [deleteNote], unless a new note has taken the place meanwhile.
  Future<void> restoreNote(NoteInfo note, String archived) => _exclusive(() async {
    final path = notePath(paths.notes.path, note.kind, note.slug);
    if (File(path).existsSync()) return; // never overwrite; the archive copy stays
    moveWithRetry(archived, path);
    notifyListeners();
  });

  /// The note as Markdown from its `# title` down (the front matter is for tools).
  /// CRLF (an editor on Windows may save one) reads like LF.
  String readNote(NoteInfo note) => withoutFrontMatter(
    File(notePath(paths.notes.path, note.kind, note.slug))
        .readAsStringSync()
        .replaceAll('\r\n', '\n'),
  );

  var _disposed = false;

  /// A background sync may finish after the app closed the session.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    stopAutoSync();
    _disposed = true;
    index.close();
    super.dispose();
  }
}

String withoutFrontMatter(String text) {
  if (!text.startsWith('---\n')) return text;
  final end = text.indexOf('\n---\n', 3);
  return end < 0 ? text : text.substring(end + 5);
}
