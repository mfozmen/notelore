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
import 'package:notelore_core/notelore_core.dart' as core show listArchived, restoreArchived;
import 'package:path/path.dart' as p;

import 'strings.dart';
import 'theme.dart';
import 'voice.dart';
import 'whisper_model.dart';
import 'whisper_native.dart';
import 'whisper_speech.dart' show MicrophoneChoice;

/// Checks a key and returns the chat models it can use.
typedef Validate = Future<List<String>> Function(ProviderSpec spec, String key);
typedef MakeProvider = LlmProvider Function(
  ProviderSpec spec,
  String? key, {
  String? model,
  BearerToken? planToken,
  bool webSearch,
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

/// The value of [values] named [name], or null.
T? _named<T extends Enum>(List<T> values, Object? name) =>
    values.where((v) => v.name == name).firstOrNull;

/// The shared app settings in the notes folder on Drive (not a note: the sync
/// engine leaves it alone).
const sharedSettings = '.notelore/settings.json';

class Session extends ChangeNotifier {
  Session(
    this.paths, {
    this.validate = validateKey,
    this.makeProvider = createProvider,
    this.today,
    this.keySpace = 'notelore',
    DateTime Function()? clock,
    this.keys = appKeys,
    this.driveAuth,
    this.remoteFor = _driveRemote,
    this.chatGpt,
    this.listPlanModels = listChatGptModels,
    this.systemLanguage = 'en',
    this._speech,
    this._voice,
    this.whisperFiles = whisperSmall,
    this.httpClient = http.Client.new,
    this.makeWhisper = nativeWhisper,
    this.listMicrophones = nativeMicrophones,
    this.localModels = true,
  }) : clock = clock ?? DateTime.timestamp,
       index = NoteIndex(p.join(paths.state.path, 'index.sqlite'), paths.notes.path),
       manifest = Manifest(paths.state.path);

  final NotelorePaths paths;
  final Validate validate;

  final Speech? _speech;
  final Voice? _voice;

  /// The device's speech recognition and voices for voice mode, made on first use.
  late final Speech _device = _speech ?? DeviceSpeech();
  late final Voice voice = _voice ?? DeviceVoice();

  /// What voice mode listens with: Whisper once downloaded (#168), the
  /// device's recognizer until then.
  Speech get speech =>
      whisper.ready ? _whisperSpeech ??= makeWhisper(whisper, () => microphone) : _device;
  Speech? _whisperSpeech;

  /// On-device Whisper, downloaded on request into this device's state.
  late final WhisperModel whisper = WhisperModel(
    p.join(paths.state.path, 'models', 'whisper-small'),
    files: whisperFiles,
  );
  final List<ModelFile> whisperFiles;
  final http.Client Function() httpClient;
  final Speech Function(WhisperModel model, String? Function() microphone) makeWhisper;

  /// The device's microphones, for Whisper to record from.
  final Future<List<MicrophoneChoice>> Function() listMicrophones;

  /// The microphone picked in Settings; null is the system default.
  String? microphone;

  void setMicrophone(String? id) {
    microphone = id;
    _saveUi();
  }

  /// From 0 to 1 while Whisper downloads; null otherwise.
  double? whisperProgress;

  /// Why the last download failed.
  String? whisperProblem;

  Future<void> downloadWhisper() async {
    if (whisperProgress != null) return;
    whisperProblem = null;
    whisperProgress = 0;
    notifyListeners();
    final client = httpClient();
    try {
      await whisper.download(
        client: client,
        onProgress: (done) {
          // Each percent, not each chunk: the screen redraws on every notify.
          if ((done * 100).floor() == (whisperProgress! * 100).floor()) return;
          whisperProgress = done;
          notifyListeners();
        },
      );
    } on Object catch (error) {
      whisperProblem = '$error'; // whatever it was, said rather than lost
    } finally {
      client.close();
      whisperProgress = null;
      notifyListeners();
    }
  }

  /// Now, for the time of a settings change (tests pass their own).
  final DateTime Function() clock;

  /// The device's language code; [AppLanguage.system] follows it.
  final String systemLanguage;

  /// The language the user picked in Settings; the device's by default.
  AppLanguage language = AppLanguage.system;

  /// The look: a nature palette, and light, dark or the device's.
  Palette palette = Palette.lagoon;
  Appearance appearance = Appearance.system;

  /// The model may look things up on the web, where its provider can (#96).
  bool webSearch = true;

  /// Turns web search on or off; the provider is rebuilt to match.
  Future<void> setWebSearch(bool on) async {
    await _applyWebSearch(on);
    _touch();
  }

  Future<void> _applyWebSearch(bool on) async {
    webSearch = on;
    _saveUi();
    if (model case final current?) await _applyModel(current);
  }

  /// The app's words in [language].
  Strings get strings => stringsFor(language, systemLanguage);

  String get _ui => p.join(paths.state.path, 'ui.json');

  /// Picks the app language and remembers it on this device.
  void setLanguage(AppLanguage chosen) {
    _applyLanguage(chosen);
    _touch();
  }

  void _applyLanguage(AppLanguage chosen) {
    language = chosen;
    _saveUi();
  }

  void setPalette(Palette chosen) {
    _applyLook(chosen, appearance);
    _touch();
  }

  void setAppearance(Appearance chosen) {
    _applyLook(palette, chosen);
    _touch();
  }

  void _applyLook(Palette chosenPalette, Appearance chosenAppearance) {
    palette = chosenPalette;
    appearance = chosenAppearance;
    _saveUi();
  }

  /// Announces the language and look, and remembers them on this device.
  void _saveUi() {
    notifyListeners();
    try {
      atomicWrite(
        _ui,
        jsonEncode({
          'language': language.name,
          'palette': palette.name,
          'appearance': appearance.name,
          'webSearch': webSearch,
          'microphone': ?microphone,
        }),
      );
    } on FileSystemException {
      // not remembered this time (a locked folder); the choice still applies now
    }
  }

  void _loadLanguage() {
    try {
      final saved = jsonDecode(File(_ui).readAsStringSync());
      if (saved is! Map) return;
      language = _named(AppLanguage.values, saved['language']) ?? AppLanguage.system;
      palette = _named(Palette.values, saved['palette']) ?? Palette.lagoon;
      appearance = _named(Appearance.values, saved['appearance']) ?? Appearance.system;
      webSearch = saved['webSearch'] != false;
      microphone = switch (saved['microphone']) {
        final String id => id,
        _ => null,
      };
    } on Exception {
      // none saved yet, or damaged: the device's language
    }
  }

  final MakeProvider makeProvider;

  /// "Sign in with ChatGPT" for the ChatGPT plan provider; null when not offered.
  final OAuthSignIn? chatGpt;
  final ListPlanModels listPlanModels;

  /// Set when the ChatGPT plan was connected for the first time on this device:
  /// the screen shows OpenAI's "You're using your ChatGPT plan" once.
  var showPlanWelcome = false;

  /// The providers this device offers.
  List<ProviderSpec> get providers => [
    for (final spec in providerSpecs)
      if ((spec.name != 'chatgpt' || chatGpt != null) && (spec.name != 'ollama' || localModels))
        spec,
  ];

  /// Models running on this machine (Ollama) are offered: not on a phone.
  final bool localModels;

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

  bool get ready => _agent != null;

  String get _settings => p.join(paths.state.path, 'settings.json');

  String _keyName(ProviderSpec spec) => '$keySpace.${spec.name}.api_key';

  /// Picks up the provider chosen on an earlier run, and syncs when Drive is
  /// connected (in the background: an offline start is fine).
  Future<void> load() async {
    _loadLanguage();
    // Whisper comes by itself, in the background: not with the app, so that
    // updates stay small.
    if (!whisper.ready) unawaited(downloadWhisper());
    await _loadProvider();
    if (ready) unawaited(_refreshQuietly());
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
    // A note-taking app needs no big model: start on the cheapest one listed (the
    // fixed default when none is). Ollama keeps its default: its list is local.
    final chosen =
        model ??
        (spec.name == 'ollama' ? null : cheapestModel(spec.name, listed)) ??
        (spec.defaultModel.isNotEmpty ? spec.defaultModel : null);
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
    _touch();
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
    if (spec.name != 'chatgpt') return currentModels(spec.name, await validate(spec, key));
    if (signIn) await chatGpt!.signIn();
    return currentModels(spec.name, await listPlanModels(chatGpt!.token));
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

  /// The model a blank choice goes back to: the cheapest listed one, else the
  /// provider's fixed default (always for Ollama, whose list is local).
  String get defaultModel {
    final current = spec!;
    return (current.name == 'ollama' ? null : cheapestModel(current.name, models)) ??
        current.defaultModel;
  }

  /// A blank [chosen] goes back to [defaultModel].
  Future<void> setModel(String chosen) async {
    await _applyModel(chosen);
    _touch();
  }

  Future<void> _applyModel(String chosen) async {
    final current = spec;
    if (current == null) return;
    final key = current.requiresApiKey ? await keys.read(key: _keyName(current)) : '';
    if (key == null) return logout(); // the keystore lost it: set up again
    final trimmed = chosen.trim();
    final next = trimmed.isEmpty ? defaultModel : trimmed;
    _save(current, next, models);
    _use(current, key, next);
  }

  /// The chosen model is not among the ones the provider lists (any more): the
  /// chat asks the user to pick another. An empty list proves nothing.
  bool get modelGone => models.isNotEmpty && model != null && !models.contains(model);

  /// New models show up by themselves: on start the list is asked for again.
  /// Offline or refused, the old list stays; the chosen model never changes.
  Future<void> _refreshQuietly() async {
    try {
      await refreshModels();
    } on Exception {
      // the old list is still good enough
    }
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
      webSearch: webSearch && chosen.webSearch,
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

  /// What the user wrote while a turn ran, not yet handed to the model.
  final _later = <String>[];

  /// The user's last message as it was sent; null before the first.
  String? get lastSent => transcript.where((l) => l.role == ChatRole.user).lastOrNull?.text;

  /// Sends [lastSent] again, as a message of its own; nothing before the first.
  Future<void> resend() async {
    if (lastSent case final message?) await send(message);
  }

  /// One chat turn, then a sync. A provider failure becomes an error line; the
  /// agent has already taken the turn back, so the user can simply send again.
  /// Sent while a turn runs, a message joins that turn instead (see [_later]).
  Future<void> send(String text) async {
    final message = text.trim();
    if (message.isEmpty) return;
    transcript.add((role: ChatRole.user, text: message));
    if (busy) {
      _later.add(message); // joins the running turn at its next step
      notifyListeners();
      return;
    }
    await _turns(message);
  }

  /// Turns until nothing written meanwhile is left; busy throughout.
  Future<void> _turns(String first) async {
    busy = true;
    notifyListeners();
    for (String? message = first; message != null; message = _rest()) {
      _stopped = false;
      final taken = <String>[];
      await _exclusive(() async {
        Agent? asked; // the one that ran the turn, even if a logout replaced it since
        try {
          if (_stopped) throw const TurnStopped(); // stopped while queued behind a sync
          final answer = await (asked = _agent!).ask(
            message!,
            takeLater: () {
              taken.addAll(_later);
              _later.clear();
              return [...taken];
            },
          );
          transcript.add((role: ChatRole.assistant, text: strings.core(answer)));
        } on Exception catch (error) {
          // The failed turn was taken back: what it had taken goes out again.
          _later.insertAll(0, taken);
          final failed = strings.core('$error');
          transcript.add((
            role: ChatRole.error,
            // Its writes stay: a resend could write them twice.
            text: asked?.wroteNotes ?? false ? '$failed\n\n${strings.notesMayBeSaved}' : failed,
          ));
        } finally {
          notifyListeners();
        }
      });
    }
    busy = false;
    notifyListeners();
    if (driveConnected) unawaited(syncNow());
  }

  /// What was written too late for the last turn (or after a Stop), as one
  /// message; null when there is none.
  String? _rest() {
    if (_later.isEmpty) return null;
    final rest = _later.join('\n\n');
    _later.clear();
    return rest;
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

  // Settings shared through Drive: the language and the provider and model, as
  // [sharedSettings] in the notes folder on Drive. The newest change wins; each
  // device keeps the time of its last change. Keys and sign-ins never travel.
  String get _changed => p.join(paths.state.path, 'settings-changed.txt');

  DateTime? get _changedAt {
    try {
      return DateTime.parse(File(_changed).readAsStringSync());
    } on Exception {
      return null; // nothing changed here yet, or unreadable
    }
  }

  void _touch([DateTime? at]) {
    try {
      atomicWrite(_changed, (at ?? clock()).toUtc().toIso8601String());
    } on FileSystemException {
      // not remembered: the next change tries again
    }
  }

  Future<void> _syncSettings(Remote remote) async {
    final listed = (await remote.list())[sharedSettings];
    final theirs = listed == null ? null : _json(await remote.download(listed.id));
    final at = DateTime.tryParse('${theirs?['updated']}');
    final mine = _changedAt;
    if (at != null && (mine == null || at.isAfter(mine))) {
      await _adopt(theirs!);
      _touch(at);
      return;
    }
    if (at != null && !mine!.isAfter(at)) return; // the same change on both sides
    final stamp = mine ?? clock();
    if (mine == null) _touch(stamp);
    final shared = {
      'updated': stamp.toUtc().toIso8601String(),
      'language': language.name,
      'palette': palette.name,
      'appearance': appearance.name,
      'webSearch': webSearch,
      'provider': ?spec?.name,
      'model': ?model,
    };
    await remote.upload(sharedSettings, utf8.encode(jsonEncode(shared)), listed?.id);
  }

  static Map<String, Object?>? _json(List<int> data) {
    try {
      return switch (jsonDecode(utf8.decode(data, allowMalformed: true))) {
        final Map<String, Object?> map => map,
        _ => null,
      };
    } on FormatException {
      return null; // damaged: replaced with this device's settings
    }
  }

  /// Another device's settings. Its provider only when this device can use it
  /// without asking (a key, or the ChatGPT sign-in); Ollama is local to each machine.
  Future<void> _adopt(Map<String, Object?> theirs) async {
    if (_named(AppLanguage.values, theirs['language']) case final l?) _applyLanguage(l);
    _applyLook(
      _named(Palette.values, theirs['palette']) ?? palette,
      _named(Appearance.values, theirs['appearance']) ?? appearance,
    );
    if (theirs['webSearch'] case final bool on when on != webSearch) await _applyWebSearch(on);
    final (name, chosen) = (theirs['provider'], theirs['model']);
    if (name is! String || chosen is! String || name == 'ollama') return;
    final found = providerSpecs.where((s) => s.name == name).firstOrNull;
    if (found == null) return;
    if (found == spec) {
      if (chosen != model) await _applyModel(chosen);
      return;
    }
    final key = found.requiresApiKey ? await keys.read(key: _keyName(found)) : '';
    if (key == null) return;
    if (found.name == 'chatgpt' && !(await chatGpt?.signedIn() ?? false)) return;
    models = const [];
    _save(found, chosen, models);
    _use(found, key, chosen);
    unawaited(_refreshQuietly()); // its model list
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
        await _syncSettings(_remote!);
        final counts = (
          report.pushed.length + report.removedRemote.length,
          report.pulled.length + report.removedLocal.length,
          report.merged.length,
          report.skipped.length,
        );
        final changed = counts.$1 + counts.$2 + counts.$3 + counts.$4 > 0;
        syncStatus = [
          strings.synced(counts.$1, counts.$2, counts.$3, counts.$4),
          // How the model settled conflicts; nothing to explain when nothing moved.
          if (changed) ...?resolver?.explanations,
        ].join(' ');
      } on NotSignedIn catch (error) {
        driveConnected = false;
        syncStatus = strings.signInAgain(error.message);
      } on NetworkError {
        syncStatus = strings.offline;
      } on HttpError catch (error) {
        syncStatus = strings.driveError(error.message);
      } on FileSystemException catch (error) {
        // Windows: antivirus or an editor holds a note past the store's retries.
        syncStatus = strings.noteInUse(error.message);
      } finally {
        _pendingSyncs--;
        notifyListeners();
      }
    });
  }

  static List<String>? _unresolved(Conflict conflict) => null;

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

  /// What was archived, newest first.
  List<ArchivedNote> listArchived() => core.listArchived(paths.notes.path);

  /// An archived note as Markdown from its title down.
  String readArchived(ArchivedNote archived) =>
      withoutFrontMatter(File(archived.path).readAsStringSync().replaceAll('\r\n', '\n'));

  /// Puts [archived] back where it came from; false when a note took the name.
  Future<bool> restoreArchived(ArchivedNote archived) => _exclusive(() async {
    try {
      core.restoreArchived(paths.notes.path, archived);
    } on RestoreTaken {
      return false;
    }
    notifyListeners();
    return true;
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
