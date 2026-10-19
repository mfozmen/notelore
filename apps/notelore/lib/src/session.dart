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
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:notelore_core/notelore_core.dart';
import 'package:notelore_core/notelore_core.dart' as core show listArchived, restoreArchived;
import 'package:path/path.dart' as p;

import 'audio_file.dart';
import 'audio_native.dart';
import 'device_auth.dart';
import 'device_model.dart';
import 'device_native.dart';
import 'lock_state.dart';
import 'pdf_native.dart';
import 'reminder_notifier.dart';
import 'strings.dart';
import 'theme.dart';
import 'transfer.dart';
import 'voice.dart';
import 'whisper_model.dart';
import 'whisper_native.dart';
import 'whisper_speech.dart' show MicrophoneChoice, Transcriber;

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
ReminderCalendar _googleCalendar(OAuthSignIn auth) => GoogleCalendar(http.Client(), auth.token);

/// [pending]: the user's message, still waiting to reach the model (offline,
/// or the provider's usage limit).
enum ChatRole { user, assistant, error, pending }

typedef ChatLine = ({ChatRole role, String text});

/// What happened to one imported file: null when it was not a note.
typedef ImportReport = ({String file, Imported? imported});

/// The value of [values] named [name], or null.
T? _named<T extends Enum>(List<T> values, Object? name) =>
    values.where((v) => v.name == name).firstOrNull;

/// The shared app settings in the notes folder on Drive (not a note: the sync
/// engine leaves it alone).
const sharedSettings = '.notelore/settings.json';

/// What went wrong with Google Calendar (#432): its sign-in, or a write the
/// next refresh tries again.
enum CalendarProblem { signIn, update }

class Session extends ChangeNotifier {
  Session(
    this.paths, {
    this.validate = validateKey,
    this.makeProvider = createProvider,
    this.today,
    this.keySpace = 'notelore',
    DateTime Function()? clock,
    Duration Function()? uptime,
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
    this.resolve = InternetAddress.lookup,
    this.makeWhisper = nativeWhisper,
    this.makeTranscriber = nativeTranscriber,
    this.decodeAudio = nativeDecodeAudio,
    this.readPdf = nativePdfText,
    this.listMicrophones = nativeMicrophones,
    this.localModels = true,
    this.deviceModels = false,
    this.deviceFiles = deviceModelFiles,
    this.makeDeviceEngine = nativeDeviceEngine,
    this.retryEvery = const Duration(minutes: 1),
    this.lockIterations = defaultIterations,
    DeviceAuth? deviceAuth,
    this.offThread = Isolate.run,
    this._exchange,
    this.timing,
    this.reminders,
    this.calendarAuth,
    this.calendarFor = _googleCalendar,
  }) : clock = clock ?? DateTime.timestamp,
       deviceAuth = deviceAuth ?? LocalDeviceAuth(),
       // Time that only moves forward; a given clock stands in for it, unless told apart.
       uptime = uptime ?? _uptimeOf(clock),
       index = NoteIndex(p.join(paths.state.path, 'index.sqlite'), paths.notes.path),
       manifest = Manifest(paths.state.path);

  final NotelorePaths paths;
  final Validate validate;

  /// Hears how long a turn waited in the queue and each model and tool call
  /// took (#232); development runs only, never note text.
  final void Function(String entry)? timing;

  /// This device's notifications for the notes' reminders (#431); none where
  /// the platform has none (and in tests that do not ask for them).
  final ReminderNotifier? reminders;

  /// Whether Notelore may notify on this device; null where it cannot at all.
  bool? remindersAllowed;

  /// Google Calendar's own grant (#432): another scope than Drive's, asked
  /// for when the switch is turned on; null in a build without Google sign-in.
  final OAuthSignIn? calendarAuth;
  final ReminderCalendar Function(OAuthSignIn auth) calendarFor;

  /// Google Calendar reminds, on every device, instead of this device's
  /// notifications. Shared through Drive, so no device reminds twice.
  bool calendar = false;

  /// Notelore's own calendar in the user's Google Calendar, shared too.
  String? calendarId;

  /// What went wrong with the calendar, for Settings to say in plain words.
  CalendarProblem? calendarProblem;

  /// While the calendar's sign-in or first write runs: the switch waits.
  var calendarBusy = false;

  /// Whether this device holds the calendar grant; null until looked at.
  bool? calendarHere;

  /// A turn here just made a reminder while the calendar is on but this
  /// device has no grant: the app offers the sign-in where it is seen.
  var calendarNudge = false;

  /// The offer was taken or put off; it is not made again on this device.
  var _calendarNudged = false;

  /// The reminders of the last pass, to tell one a turn just made; null
  /// before the first.
  Set<int>? _knownDue;

  void calendarNudgeLater() {
    calendarNudge = false;
    _calendarNudged = true;
    _saveUi();
  }

  bool get calendarAvailable => calendarAuth != null;

  /// Asked once a run at most: a refusal is not asked again until Allow.
  var _askedReminders = false;

  /// Whether the scheduled reminders hide their words (the app lock was on);
  /// null until scheduled this run, so the first time schedules them all anew.
  bool? _scheduledPrivately;

  /// The lock turned on or off: the notifications follow (#431).
  void _lockChanged() {
    notifyListeners();
    if (_scheduledPrivately case final private? when private != lock.enabled) {
      unawaited(refreshReminders(ask: false));
    }
  }

  /// Where exports go and imports come from (#215): the share sheet on a phone,
  /// save and open dialogs on the desktop.
  late final Exchange exchange =
      _exchange ?? Exchange(mobile: Platform.isAndroid || Platform.isIOS);
  final Exchange? _exchange;

  /// The app lock's hash strength, and where its slow hashing runs (off the
  /// UI thread, so a phone does not stutter while it checks a PIN).
  final int lockIterations;

  /// The device's own lock (#295): pattern, PIN, fingerprint, face, Windows
  /// Hello or Touch ID, through local_auth; tests pass a fake.
  final DeviceAuth deviceAuth;
  final Future<R> Function<R>(FutureOr<R> Function() work) offThread;

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

  /// The chat model that runs on this device (#328), downloaded on request
  /// like Whisper: checked, resumable, kept in this device's state.
  late final WhisperModel deviceModel = WhisperModel(
    p.join(paths.state.path, 'models', 'device'),
    files: deviceFiles,
  );
  final List<ModelFile> deviceFiles;

  /// The engine that runs [deviceModel]'s file: llama.cpp; a fake in tests.
  final LocalEngine Function(String path) makeDeviceEngine;

  /// The one loaded engine, if any: a rebuilt provider reuses it, never a
  /// second copy of the model in memory.
  LocalEngine? _deviceEngine;

  /// [chosen]'s provider: the model on the device runs on the one engine.
  LlmProvider _providerFor(ProviderSpec chosen, String key, String chosenModel) {
    if (chosen.name == 'device') {
      return LocalProvider(
        chosenModel,
        _deviceEngine ??= makeDeviceEngine(deviceModel.path(deviceFiles.first.name)),
      );
    }
    return makeProvider(
      chosen,
      key,
      model: chosenModel,
      planToken: chosen.name == 'chatgpt' ? chatGpt!.token : null,
      webSearch: webSearch && chosen.webSearch,
    );
  }

  /// Lets go of the model on the device, when another model is used or none.
  Future<void> _freeDeviceEngine() async {
    final engine = _deviceEngine;
    _deviceEngine = null;
    await engine?.dispose();
  }

  /// The model on the device is offered (where llama.cpp runs: Android,
  /// Windows, macOS).
  final bool deviceModels;

  /// From 0 to 1 while the device model downloads, else null.
  double? deviceProgress;

  /// Why the last device model download failed, if it did.
  String? deviceProblem;

  /// One download at a time; a second call waits for the one running.
  Future<void> downloadDeviceModel() => _deviceDownload ??= _fetch(
    deviceModel,
    (done) => deviceProgress = done,
    (why) => deviceProblem = why,
  ).whenComplete(() => _deviceDownload = null);
  Future<void>? _deviceDownload;

  final List<ModelFile> whisperFiles;
  final http.Client Function() httpClient;

  /// How the link reader finds a host's addresses, to stay off private ones (#315).
  final Resolve resolve;
  final Speech Function(WhisperModel model, String? Function() microphone) makeWhisper;

  /// Whisper over an attached audio file (#285), and the platform's decoder
  /// for what is not WAV (null where there is none).
  final Transcriber Function(WhisperModel model) makeTranscriber;
  final Future<Float32List?> Function(Uint8List bytes) decodeAudio;
  Transcriber? _fileTranscriber;

  /// Keeps an attached file's original beside the notes (#279), synced with
  /// them; its path for the note to link, or null when it cannot be written
  /// (the words still go).
  String? keepOriginal(String name, List<int> bytes) {
    try {
      return keepAttachment(paths.notes.path, name, bytes, today: today);
    } on FileSystemException {
      return null;
    }
  }

  /// An attached audio file's words, heard on this device (#285); null when no
  /// words are heard. Throws [AudioUnavailable] before Whisper is here, and
  /// [AudioUnreadable] for a format this device cannot open.
  Future<String?> audioText(Uint8List bytes) async {
    if (!whisper.ready) throw const AudioUnavailable();
    final samples = wavSamples(bytes) ?? await decodeAudio(bytes);
    if (samples == null) throw const AudioUnreadable();
    return transcribeSamples(
      samples,
      _fileTranscriber ??= makeTranscriber(whisper),
      strings.languageCode,
    );
  }

  /// An attached PDF's text (#284); throws on a damaged file.
  final Future<String> Function(Uint8List bytes) readPdf;

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
    await _fetch(whisper, (done) => whisperProgress = done, (why) => whisperProblem = why);
  }

  /// Downloads [model], telling [progress] (null when over) and [problem].
  Future<void> _fetch(
    WhisperModel model,
    void Function(double? done) progress,
    void Function(String? why) problem,
  ) async {
    var shown = 0.0;
    problem(null);
    progress(shown);
    notifyListeners();
    final client = httpClient();
    try {
      await model.download(
        client: client,
        onProgress: (sent) {
          // A server that sends more than it should never shows past 100%.
          final done = sent.clamp(0.0, 1.0);
          // Each percent, not each chunk: the screen redraws on every notify.
          if ((done * 100).floor() == (shown * 100).floor()) return;
          progress(shown = done);
          notifyListeners();
        },
      );
    } on Object catch (error) {
      problem('$error'); // whatever it was, said rather than lost
    } finally {
      client.close();
      progress(null);
      notifyListeners();
    }
  }

  /// Now, for the time of a settings change (tests pass their own).
  final DateTime Function() clock;

  /// Time since start that setting the device clock does not move (#315).
  final Duration Function() uptime;

  static Duration Function() _uptimeOf(DateTime Function()? clock) {
    if (clock == null) {
      final watch = Stopwatch()..start();
      return () => watch.elapsed;
    }
    final start = clock();
    return () => clock().difference(start);
  }

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
          if (calendar) 'calendar': true,
          'calendarId': ?calendarId,
          'microphone': ?microphone,
          if (setUpBefore) 'setUp': true,
          if (advanced) 'advanced': true,
          if (_calendarNudged) 'calendarNudged': true,
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
      calendar = saved['calendar'] == true;
      _calendarNudged = saved['calendarNudged'] == true;
      calendarId = switch (saved['calendarId']) {
        final String id => id,
        _ => null,
      };
      setUpBefore = saved['setUp'] == true;
      advanced = saved['advanced'] == true;
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
      if ((spec.name != 'chatgpt' || chatGpt != null) &&
          (spec.name != 'ollama' || localModels) &&
          (spec.name != 'device' || deviceModels))
        spec,
  ];

  /// Models running on this machine (Ollama) are offered: not on a phone.
  final bool localModels;

  /// How often messages that wait are tried again by themselves.
  final Duration retryEvery;

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

  /// The tokens the model calls used, this conversation and on this device (#217).
  late final usage = UsageMeter(
    p.join(paths.state.path, 'usage.json'),
    today: () => today ?? clock().toLocal(),
  );

  /// Settings shows what only advanced users want, such as usage (#294).
  var advanced = false;

  void setAdvanced(bool on) {
    advanced = on;
    _saveUi();
  }

  Remote? _remote;
  var driveConnected = false;
  var _pendingSyncs = 0;

  /// A sync is running or queued.
  bool get syncing => _pendingSyncs > 0;

  /// What the last sync did, for the settings screen; null before any.
  String? syncStatus;

  /// Whether this run already said the notes moved into Drive's hidden storage.
  var _toldMoved = false;

  /// Notes gone from Drive with too many others at once (#454): kept here
  /// until the person restores them to Drive or deletes them here too.
  List<String> heldNotes = const [];

  /// The [heldNotes] as the person knows them: each note's title, or its file
  /// name when it does not read as a note (an attachment, say).
  List<String> get heldTitles => heldNotes.map(_titleOf).toList();

  String _titleOf(String rel) {
    try {
      return parse(File(p.joinAll([paths.notes.path, ...rel.split('/')])).readAsStringSync()).title;
    } on Exception {
      return rel.split('/').last;
    }
  }

  /// Puts the [heldNotes] back on Drive.
  Future<void> restoreHeld() => syncNow(restore: {...heldNotes});

  /// Removes the [heldNotes] here too: they move to history, like one note
  /// removed in Drive.
  Future<void> deleteHeld() => syncNow(remove: {...heldNotes});

  /// Chat turns and syncs, one after the other.
  Future<void> _queue = Future.value();

  /// Completes when everything queued so far is done.
  Future<void> get syncDone => _queue;

  bool get driveAvailable => driveAuth != null;

  /// Notelore is for Google accounts (#208): a build that can sign in asks for
  /// it first, until this device has signed in once. After that it opens even
  /// offline or with the grant expired (Settings connects again); signing out
  /// (disconnecting Drive) asks again.
  bool get needsGoogle => driveAvailable && !_google;
  var _google = false;

  /// `in` once this device signed in with Google, `out` once it signed out.
  File get _googleMark => File(p.join(paths.state.path, 'google-signed-in'));

  void _markGoogle({required bool signedIn}) {
    _google = signedIn;
    (_googleMark..parent.createSync(recursive: true)).writeAsStringSync(signedIn ? 'in' : 'out');
  }

  /// From the mark; a device without one (set up before #208) counts as signed
  /// in when it is connected now or has synced before, which holds offline too.
  void _loadGoogle() {
    final mark = _googleMark.existsSync() ? _googleMark.readAsStringSync() : null;
    if (mark == null && (driveConnected || manifest.paths().isNotEmpty)) {
      _markGoogle(signedIn: true);
    } else {
      _google = mark == 'in';
    }
  }

  final transcript = <ChatLine>[];

  /// What is written in the message box and not sent yet; it outlives the chat
  /// screen, so a trip to another tab (or a new window layout) keeps it.
  var draft = '';
  var sharedDraftVersion = 0;

  /// A share is untrusted input: show it for editing, never send it on receipt.
  void receiveSharedText(String text) {
    draft = draft.isEmpty ? text : '$draft\n\n$text';
    sharedDraftVersion++;
    notifyListeners();
  }

  bool busy = false;

  bool get ready => _agent != null;

  /// The system prompt of the wizard's one test turn (#361).
  static const trySystem = 'You are Notelore. Reply in one short sentence, in the language asked.';

  /// One real turn with the connected model, no tools and no notes: the answer
  /// shows the user it works. It costs a few tokens, as the wizard says.
  Future<String> tryModel() async {
    // Not metered: a few tokens to say hello are not the conversation's use.
    final provider = switch (_provider!) {
      MeteredProvider(:final provider) => provider,
      final other => other,
    };
    final answer = await provider.turn(trySystem, [
      {'role': 'user', 'content': strings.tryPrompt},
    ], const []);
    return answer.content.map((b) => b['text'] ?? '').join().trim();
  }

  /// A model was in use on this device once (#363): with none now, the app
  /// still opens, and the chat asks for one; only a fresh device starts with
  /// the wizard. Logout forgets it.
  var setUpBefore = false;

  /// The first-run wizard has connected a model and is showing its last step:
  /// the app stays on it until [finishSetup] (#357).
  var finishingSetup = false;

  void finishSetup() {
    finishingSetup = false;
    notifyListeners();
  }

  String get _settings => p.join(paths.state.path, 'settings.json');

  String _keyName(ProviderSpec spec) => '$keySpace.${spec.name}.api_key';

  /// The app lock (#224), with its own state; the screens hear of its changes
  /// through this session.
  late final AppLock lock = AppLock(
    keys: keys,
    keySpace: keySpace,
    clock: clock,
    uptime: uptime,
    iterations: lockIterations,
    offThread: offThread,
    changed: _lockChanged,
    device: deviceAuth,
  );

  /// Picks up the provider chosen on an earlier run, and syncs when Drive is
  /// connected (in the background: an offline start is fine).
  Future<void> load() async {
    await lock.load();
    _loadLanguage();
    // Whisper comes by itself, in the background: not with the app, so that
    // updates stay small.
    if (!whisper.ready) unawaited(downloadWhisper());
    await _loadProvider();
    _loadQueue();
    if (ready) {
      unawaited(_refreshQuietly());
      unawaited(retryNow());
    }
    driveConnected = await driveAuth?.signedIn() ?? false;
    _loadGoogle();
    // Signed in to Google before, and Drive's grant no longer holds: on a phone
    // the grant lacks drive.appdata since v0.17.0 (#479). Say so, never stop
    // syncing in silence.
    if (_google && driveAuth != null && !driveConnected) {
      _needSignIn(strings.drivePermissionAgain, 'no grant for the Drive scopes at start');
    }
    await refreshReminders(ask: false); // nothing pops up at start, over the lock too
    notifyListeners();
    if (driveConnected) unawaited(syncNow());
  }

  /// The saved provider settings; null on a first run or when damaged.
  Object? _readSettings() {
    try {
      return jsonDecode(File(_settings).readAsStringSync());
    } on FileSystemException {
      return null; // first run
    } on FormatException {
      return null; // damaged: set up again
    }
  }

  Future<void> _loadProvider() async {
    final saved = _readSettings();
    if (saved case {'provider': final String name, 'model': final String chosen}) {
      final found = providerSpecs.where((s) => s.name == name).firstOrNull;
      if (found == null) return;
      final key = found.requiresApiKey ? await keys.read(key: _keyName(found)) : '';
      if (key == null) return; // the keystore lost it: set up again
      if (found.name == 'chatgpt' && !(await chatGpt?.signedIn() ?? false)) return;
      if (found.name == 'ollama') await _markOllama(found);
      models = switch (saved['models']) {
        final List<Object?> listed => listed.whereType<String>().toList(),
        _ => const [], // settings from before the model list
      };
      _use(found, key, chosen);
    }
  }

  /// An Ollama set up before its mark existed (#356): [connections] lists it too.
  Future<void> _markOllama(ProviderSpec ollama) async {
    if (await keys.read(key: _keyName(ollama)) == null) {
      await keys.write(key: _keyName(ollama), value: '');
    }
  }

  /// Checks [key] with the provider, then remembers it. Throws
  /// [KeyValidationError] or [TransientValidationError] and changes nothing.
  /// The key and the settings are saved together: if the settings cannot be
  /// written, the key is taken back out of the keystore.
  Future<void> connect(ProviderSpec spec, String key, {String? model}) =>
      _connect(spec, key, model: model, signIn: true);

  /// Every model this device can switch to without setting it up again (#356):
  /// a stored key (Ollama keeps an empty one as its mark), or the plan signed in.
  Future<List<ProviderSpec>> connections() async => [
    for (final spec in providers)
      if (spec.name == 'chatgpt'
          ? await chatGpt!.signedIn()
          : await keys.read(key: _keyName(spec)) != null)
        spec,
  ];

  /// Back to a connected model with its stored key, checked again; never opens
  /// a browser. Throws [StateError] when it is not connected (any more).
  Future<void> switchTo(ProviderSpec spec) async {
    final key = spec.name == 'chatgpt' ? '' : await keys.read(key: _keyName(spec));
    if (key == null) throw StateError('${spec.displayName} is not connected');
    await _connect(spec, key, signIn: false);
  }

  /// Forgets one model's key or sign-in. The active one leaves no model until
  /// another is chosen; the notes and the conversation stay.
  Future<void> disconnect(ProviderSpec spec) async {
    if (spec.name == 'chatgpt') {
      await chatGpt?.signOut();
    } else {
      await keys.delete(key: _keyName(spec));
    }
    if (spec.name == 'device') {
      // Removed means removed: its 2.5 GB go too (downloaded again on request),
      // once a download that runs has ended, so it never writes into nothing.
      await _deviceDownload;
      await _freeDeviceEngine();
      final dir = Directory(deviceModel.dir);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
    if (this.spec?.name == spec.name) _forgetProvider();
    notifyListeners();
  }

  Future<void> _connect(
    ProviderSpec spec,
    String key, {
    required bool signIn,
    String? model,
  }) async {
    final trimmed = key.trim();
    final listed = await _models(spec, trimmed, signIn: signIn);
    // A note-taking app needs no big model: start on the cheapest one listed (the
    // fixed default when none is). Ollama keeps its default: its list is local.
    final chosen = model ?? _startModel(spec, listed) ?? _fallback(spec);
    // Every provider but the plan keeps its entry, Ollama an empty one: that is
    // how [connections] knows it.
    final keyed = spec.name != 'chatgpt';
    final name = _keyName(spec);
    final previous = keyed ? await keys.read(key: name) : null;
    if (keyed) await keys.write(key: name, value: trimmed);
    try {
      _save(spec, chosen, listed);
    } catch (_) {
      if (keyed) await _restoreKey(name, previous);
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
    if (spec.name == 'device') {
      // Its one model, once its file is here; nothing to ask a server.
      if (!deviceModel.ready) throw const TransientValidationError('Download the model first');
      return [spec.defaultModel];
    }
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

  /// The model a blank choice goes back to: the one [_startModel] picks, else
  /// the provider's fixed default.
  String get defaultModel {
    final current = spec!;
    return _startModel(current, models) ?? current.defaultModel;
  }

  /// Nothing listed to start on: the fixed default, but never for Ollama, which
  /// can only talk with a model it has (#471).
  static String _fallback(ProviderSpec spec) => switch (spec) {
    ProviderSpec(name: 'ollama') => throw const NoLocalModel(),
    ProviderSpec(:final defaultModel) when defaultModel.isNotEmpty => defaultModel,
    _ => throw TransientValidationError('${spec.displayName} lists no models'),
  };

  /// Which of [listed] a provider starts on. Ollama: one that is installed,
  /// Notelore's own first (#471). Gemini: its default when listed, the model a
  /// free AI Studio key has quota for; the cheapest listed is often a lite or
  /// preview one with none (#400). Any other: the cheapest listed.
  static String? _startModel(ProviderSpec spec, List<String> listed) => switch (spec.name) {
    'ollama' => ollamaStartModel(listed),
    'device' => null,
    'gemini' when listed.contains(spec.defaultModel) => spec.defaultModel,
    _ => cheapestModel(spec.name, listed),
  };

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

  /// No model chosen: the settings go, the agent with them.
  void _forgetProvider() {
    final settings = File(_settings);
    if (settings.existsSync()) settings.deleteSync();
    spec = null;
    model = null;
    models = const [];
    _agent = null;
    _provider = null;
    unawaited(_freeDeviceEngine());
  }

  /// Forgets every provider's key on this device and the chosen provider; the
  /// notes stay.
  Future<void> logout() async {
    _outbox.clear(); // dropped with the conversation, never run against another login
    _saveQueue();
    _stopRetrying();
    for (final spec in providerSpecs.where((s) => s.name != 'chatgpt')) {
      await keys.delete(key: _keyName(spec));
    }
    await chatGpt?.signOut();
    _forgetProvider();
    setUpBefore = false;
    _saveUi();
    transcript.clear();
    usage.newConversation();
    draft = '';
    notifyListeners();
  }

  void _use(ProviderSpec chosen, String key, String chosenModel) {
    if (!setUpBefore) {
      setUpBefore = true;
      _saveUi();
    }
    spec = chosen;
    model = chosenModel;
    if (chosen.name != 'device') unawaited(_freeDeviceEngine());
    final toolbox = Toolbox(paths.notes.path, index, today: today);
    _provider = MeteredProvider(_providerFor(chosen, key, chosenModel), chosen.name, usage);
    // A model switch keeps the conversation; logout has already dropped it.
    final history = _agent?.messages ?? const <Message>[];
    _agent = Agent(
      _provider!,
      toolbox,
      today: today,
      timing: timing,
      slim: chosen.name == 'device', // every token is read on the phone first (#447)
    )..messages.addAll(history);
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
    // A provider switched to since cannot take the images: the words only.
    final images = acceptsImages ? _lastImages : const <Block>[];
    if (lastSent case final message?) await send(message, images: images);
  }

  /// The model takes images with a message (#278): the provider's do.
  bool get acceptsImages => spec?.images ?? false;

  /// The images of the last message, for [resend]; only ever in memory.
  var _lastImages = const <Block>[];

  /// One chat turn, then a sync. A provider failure becomes an error line; the
  /// agent has already taken the turn back, so the user can simply send again.
  /// Sent while a turn runs, a message joins that turn instead (see [_later]).
  /// [images] go with this turn only, never into the queue or a saved file:
  /// the chat sends them only when nothing runs or waits ([acceptsImages]).
  Future<void> send(String text, {List<Block> images = const []}) async {
    final message = text.trim();
    // No model to answer (#363): the chat asks for one; nothing to send with.
    if (message.isEmpty || !ready) return;
    _lastImages = images;
    // Behind a waiting message, a new one waits too (kept, in order), even while
    // the waiting ones are being tried.
    if (_outbox.isNotEmpty) {
      _enqueue(message);
      return retryNow();
    }
    transcript.add((role: ChatRole.user, text: message));
    if (busy) {
      _later.add(message); // joins the running turn at its next step
      notifyListeners();
      return;
    }
    await _turns(message, images: images);
  }

  /// Turns until nothing written meanwhile is left; busy throughout. [images]
  /// go with the first.
  Future<void> _turns(String first, {bool queued = false, List<Block> images = const []}) async {
    busy = true;
    _halted = false;
    notifyListeners();
    String? message = first;
    var fromQueue = queued;
    var pictures = images;
    while (message != null) {
      _stopped = false; // before the queue: a Stop while it waits behind a sync still counts
      final (current, wasQueued, withImages) = (message, fromQueue, pictures);
      final waiting = Stopwatch()..start();
      await _exclusive(() {
        timing?.call('queue ${waiting.elapsedMilliseconds} ms');
        return _turn(current, queued: wasQueued, images: withImages);
      });
      (message, fromQueue) = _next();
      pictures = const [];
    }
    busy = false;
    notifyListeners();
    if (driveConnected) unawaited(syncNow());
  }

  /// The next message to run and whether it comes from the queue: none once
  /// one had to wait (the rest waits behind it).
  (String?, bool) _next() {
    if (_halted) return (null, false);
    if (_outbox.isNotEmpty) return (_outbox.first, true);
    return (_rest(), false);
  }

  /// One chat turn: the answer, or what its failure means.
  Future<void> _turn(String message, {required bool queued, required List<Block> images}) async {
    final taken = <String>[];
    Agent? asked; // the one that ran the turn, even if a logout replaced it since
    // For the usage page (#481): counts only, never a word of the turn.
    final watch = Stopwatch()..start();
    final metered = _provider;
    var before = 0;
    var toolCalls = 0;
    var failed = false;
    try {
      if (_stopped) throw const TurnStopped(); // stopped while queued behind a sync
      final withPages = await _withPages(message);
      if (_stopped) throw const TurnStopped(); // stopped while the pages loaded
      before = _agent!.messages.length;
      final answer = await (asked = _agent!).ask(
        _withArchived(withPages),
        images: images,
        takeLater: () {
          taken.addAll(_later);
          _later.clear();
          return [...taken];
        },
      );
      if (queued) _sent(message);
      toolCalls = _toolCalls(asked.messages.skip(before));
      transcript.add((role: ChatRole.assistant, text: strings.core(answer)));
      // Seen only once answered: a failed turn's notice goes out again.
      _lastNotes = _noteTitles(); // the agent's own changes included
      if (asked.wroteNotes) await refreshReminders();
    } on Exception catch (error) {
      failed = !_stopped; // the person's own Stop is no error
      // The failed turn was taken back: what it had taken goes out again.
      _later.insertAll(0, taken);
      _failed(
        error,
        message,
        wrote: asked?.wroteNotes ?? false,
        queued: queued,
        images: images.isNotEmpty,
      );
    } finally {
      if (metered is MeteredProvider) {
        usage.recordTurn(
          metered.name,
          metered.model,
          took: watch.elapsed,
          toolCalls: toolCalls,
          wrote: asked?.wroteNotes ?? false,
          failed: failed,
        );
      }
      notifyListeners();
    }
  }

  static int _toolCalls(Iterable<Message> messages) => [
    for (final message in messages)
      if (message['content'] case final List<Object?> blocks)
        for (final block in blocks)
          if (block is Map && block['type'] == 'tool_use') block,
  ].length;

  /// A failed turn: offline or over the provider's usage limit, the message
  /// waits and goes out later by itself; anything else is an error line. Not
  /// when the turn wrote notes: a rerun could write them twice, so the error
  /// line says so instead.
  ///
  /// A message with [images] never waits (no picture is kept): it is an error
  /// line that says to send it again (#278).
  void _failed(
    Exception error,
    String message, {
    required bool wrote,
    required bool queued,
    required bool images,
  }) {
    final later = error is NetworkError || (error is HttpError && error.status == 429);
    if (later && !wrote && !images) return _hold(message, fresh: !queued);
    if (queued) _sent(message); // it reached the model: no longer waiting
    transcript.add((
      role: ChatRole.error,
      text: [
        strings.chatError(error),
        if (wrote) strings.notesMayBeSaved,
        if (later && images) strings.imagesCannotWait,
      ].join('\n\n'),
    ));
  }

  /// Messages waiting to go out, oldest first; kept in the state folder, so a
  /// restart loses none.
  final _outbox = <String>[];

  /// The running turns stopped at a message that has to wait.
  var _halted = false;
  Timer? _retry;

  String get _pending => p.join(paths.state.path, 'pending.json');

  /// [message] waits: a [fresh] one joins the end of the queue, shown as waiting.
  void _hold(String message, {required bool fresh}) {
    _halted = true;
    if (fresh) _enqueue(message);
    // What was written meanwhile waits behind it, kept too.
    _later.forEach(_enqueue);
    _later.clear();
    _startRetrying();
    notifyListeners();
  }

  /// [message] joins the end of the queue, shown as waiting and kept.
  void _enqueue(String message) {
    _outbox.add(message);
    final at = transcript.lastIndexWhere((l) => l.role == ChatRole.user && l.text == message);
    final line = (role: ChatRole.pending, text: message);
    at < 0 ? transcript.add(line) : transcript[at] = line;
    _saveQueue();
    _startRetrying();
    notifyListeners();
  }

  void _startRetrying() => _retry ??= Timer.periodic(retryEvery, (_) => unawaited(retryNow()));

  /// The first waiting [message] reached the model.
  void _sent(String message) {
    // Logged out meanwhile: the queue went with the conversation.
    if (_outbox.firstOrNull != message) return;
    _outbox.removeAt(0);
    final at = transcript.indexWhere((l) => l.role == ChatRole.pending && l.text == message);
    if (at >= 0) transcript[at] = (role: ChatRole.user, text: message);
    _saveQueue();
    if (_outbox.isEmpty) _stopRetrying();
  }

  void _stopRetrying() {
    _retry?.cancel();
    _retry = null;
  }

  /// Sends what waits, oldest first; nothing while a turn runs.
  Future<void> retryNow() async {
    if (busy || !ready || _outbox.isEmpty) return;
    await _turns(_outbox.first, queued: true);
  }

  void _saveQueue() {
    try {
      atomicWrite(_pending, jsonEncode(_outbox));
    } on FileSystemException {
      // not kept this time (a locked folder); it still waits while the app runs
    }
  }

  void _loadQueue() {
    try {
      final saved = jsonDecode(File(_pending).readAsStringSync());
      for (final message in saved is List ? saved.whereType<String>() : const <String>[]) {
        _outbox.add(message);
        transcript.add((role: ChatRole.pending, text: message));
      }
    } on Exception {
      // none yet, or damaged: nothing waits
    }
    if (_outbox.isNotEmpty) _startRetrying();
  }

  /// The app went to the background ([foreground] false) or came back: back,
  /// what waits is tried at once (a phone holds back the network meanwhile).
  void setForeground(bool foreground) {
    if (foreground) unawaited(retryNow());
  }

  /// The notes there were after the last turn, by kind and slug.
  Map<String, String>? _lastNotes;

  Map<String, String> _noteTitles() => {
    for (final note in listNotes()) '${note.kind}/${note.slug}': note.title,
  };

  /// [message] with the text of the web pages it links to (#211), so a shared
  /// link is filed by what it says.
  Future<String> _withPages(String message) async {
    final client = httpClient();
    try {
      return await withLinkedPages(message, client: client, resolve: resolve);
    } finally {
      client.close();
    }
  }

  /// [message], and the notes archived since the last turn (here, on another
  /// device, anywhere): the model may have read them before and must not use them.
  String _withArchived(String message) {
    final now = _noteTitles();
    final gone = [
      for (final MapEntry(:key, :value) in (_lastNotes ?? const {}).entries)
        if (!now.containsKey(key)) value,
    ];
    if (gone.isEmpty) return message;
    return '$message\n\n(Notelore: moved to the archive since the last message, so not to be '
        'used: ${gone.join(', ')}.)';
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

  /// This device signed in to Google before, but Drive needs a sign-in again:
  /// its grant lacks a scope (#479), or was revoked. The app says so in a
  /// banner and the Drive status, in plain words (#480).
  var driveNeedsSignIn = false;

  /// Drive refused the sync: a 401 even after a fresh token is a sign-in
  /// again; a full Drive says so (only Drive's storage quota, never a rate
  /// limit, which would have the person delete things for nothing).
  void _driveFailed(HttpError error) {
    if (error.status == 401) return _needSignIn(strings.signedOutOfGoogle, error.message);
    if (kDebugMode) debugPrint('Google Drive: ${error.message}'); // the log only
    final full = error.message.toLowerCase().contains('storage quota');
    syncStatus = full ? strings.driveFull : strings.driveUnreachable;
  }

  void _needSignIn(String status, String detail) {
    // A sync still running when the user signed out never asks them back in.
    if (!_google) return;
    if (kDebugMode) debugPrint('Google Drive needs a sign-in: $detail'); // the log only
    driveConnected = false;
    driveNeedsSignIn = true;
    syncStatus = status;
  }

  /// Interactive Google sign-in, then the first sync. Throws [SignInFailed].
  Future<void> connectDrive() async {
    await driveAuth!.signIn();
    driveConnected = true;
    driveNeedsSignIn = false;
    _markGoogle(signedIn: true);
    notifyListeners();
    await syncNow();
  }

  Future<void> disconnectDrive() async {
    await driveAuth!.signOut();
    driveConnected = false;
    _markGoogle(signedIn: false);
    syncStatus = null;
    driveNeedsSignIn = false;
    heldNotes = const [];
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
      'calendar': calendar,
      'calendarId': ?calendarId,
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
    if (theirs['calendar'] case final bool on) {
      calendar = on;
      if (theirs['calendarId'] case final String id) calendarId = id;
      _saveUi();
    }
    final (name, chosen) = (theirs['provider'], theirs['model']);
    // A local model is this machine's own: another device's choice of one stays there.
    if (name is! String || chosen is! String || name == 'ollama' || name == 'device') return;
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

  /// One sync; the notes in [restore] go back to Drive as new, those in
  /// [remove] follow Drive's removal however many there are.
  Future<void> syncNow({Set<String> restore = const {}, Set<String> remove = const {}}) async {
    if (!driveConnected) return;
    _pendingSyncs++;
    notifyListeners();
    await _exclusive(() async {
      var completed = false;
      try {
        final resolver = _provider == null ? null : ModelResolver(askProvider(_provider!));
        final report = await sync(
          paths.notes.path,
          manifest,
          _remote ??= remoteFor(driveAuth!),
          resolver?.call ?? _unresolved, // no model connected: conflicts wait
          remove: remove,
          restore: restore,
        );
        heldNotes = report.held;
        _markSyncedNotes(report);
        completed = true;
        await _syncSettings(_remote!);
        await refreshReminders(ask: false); // the notes' and the shared setting's
        syncStatus = _syncSummary(report, resolver);
      } on MissingDriveGrant catch (error) {
        _needSignIn(strings.drivePermissionAgain, error.message);
      } on NotSignedIn catch (error) {
        _needSignIn(strings.signedOutOfGoogle, error.message);
      } on NetworkError {
        syncStatus = strings.offline;
      } on HttpError catch (error) {
        _driveFailed(error);
      } on FileSystemException catch (error) {
        // Windows: antivirus or an editor holds a note past the store's retries.
        syncStatus = strings.noteInUse(error.message);
      } finally {
        if (!completed) index.invalidateAll();
        _pendingSyncs--;
        notifyListeners();
      }
    });
  }

  /// What a finished sync says: what moved, how the model settled conflicts,
  /// and once, that the notes moved into Drive's hidden storage (#454).
  String _syncSummary(SyncReport report, ModelResolver? resolver) {
    final counts = (
      report.pushed.length + report.removedRemote.length,
      report.pulled.length + report.removedLocal.length,
      report.merged.length,
      report.skipped.length,
    );
    final changed = counts.$1 + counts.$2 + counts.$3 + counts.$4 > 0;
    final summary = [
      strings.synced(counts.$1, counts.$2, counts.$3, counts.$4),
      // How the model settled conflicts; nothing to explain when nothing moved.
      if (changed) ...?resolver?.explanations,
      if (_remote!.moved && !_toldMoved) strings.notesMoved,
    ].join(' ');
    _toldMoved = _remote!.moved; // said once
    return summary;
  }

  /// Schedules the notes' coming reminders on this device (#431): at start,
  /// after a turn that wrote notes and after a sync, so the device's schedule
  /// always equals the notes. After a turn (the user just asked for one) it
  /// may [ask] for notifications, once a run. A device that cannot notify
  /// changes nothing else.
  Future<void> refreshReminders({bool ask = true}) => _reminderRuns = _reminderRuns
      .catchError((Object _) {})
      .then((_) => _refreshReminders(ask: ask));

  /// One run at a time: a resume, a sync and a turn can all ask at once; a
  /// run that broke never stops the next.
  Future<void> _reminderRuns = Future.value();

  Future<void> _refreshReminders({required bool ask}) async {
    final root = paths.notes.path;
    final now = clock().toLocal();
    var due = await offThread(() => upcomingReminders(root, now: now));
    // With the app lock on, nothing of the notes shows: not on a locked
    // phone's screen, not in Google Calendar.
    final private = lock.enabled;
    if (private) {
      due = [for (final r in due) DueReminder(r.id, r.at, 'Notelore', strings.reminderHidden)];
    }
    final anew = private != _scheduledPrivately;
    _scheduledPrivately = private;
    // Google Calendar reminds where this device holds its grant: this device
    // then none, never twice. Without the grant here (another device turned
    // the calendar on), or in a build that cannot reach it, this device keeps
    // reminding; signed in later, the same pass cancels its own.
    final viaCalendar = calendar && await _holdsCalendar();
    await _remindOnDevice(viaCalendar ? const [] : due, ask: ask, anew: anew);
    if (viaCalendar) await _remindInCalendar(due, now);
    final known = _knownDue;
    _knownDue = {for (final r in due) r.id};
    final made = ask && known != null && due.any((r) => !known.contains(r.id));
    // Only while it fits: it goes once the calendar is off or this device holds the grant.
    final nudge = calendar && calendarHere == false && (calendarNudge || made && !_calendarNudged);
    if (nudge != calendarNudge) {
      calendarNudge = nudge;
      notifyListeners();
    }
  }

  /// Whether this device holds the calendar grant, kept in [calendarHere]
  /// for Settings. A keystore that cannot tell keeps what was known, so a
  /// passing error never makes this device remind beside Google; not known
  /// yet, it counts as no grant and this device reminds.
  Future<bool> _holdsCalendar() async {
    final auth = calendarAuth;
    if (auth == null) return false;
    final before = calendarHere;
    try {
      calendarHere = await auth.signedIn();
    } on Exception {
      calendarHere = before ?? false;
    }
    if (calendarHere != before) notifyListeners();
    return calendarHere!;
  }

  Future<void> _remindOnDevice(
    List<DueReminder> due, {
    required bool ask,
    required bool anew,
  }) async {
    final device = reminders;
    if (device == null) return;
    final wasAllowed = remindersAllowed;
    try {
      var allowed = await device.isAllowed();
      if (!allowed && ask && due.isNotEmpty && !_askedReminders) {
        _askedReminders = true;
        allowed = await device.ask();
      }
      remindersAllowed = allowed;
      await scheduleReminders(device, due, anew: anew);
    } on Exception {
      return; // no notifications here: the reminders stay in the notes
    } finally {
      if (remindersAllowed != wasAllowed) notifyListeners(); // Settings shows it
    }
  }

  /// Writes the coming reminders as events in Notelore's calendar; only on a
  /// device that holds the calendar grant.
  Future<void> _remindInCalendar(List<DueReminder> due, DateTime now) async {
    final auth = calendarAuth!;
    final before = calendarProblem;
    try {
      final google = calendarFor(auth);
      final id = await google.calendarId(calendarId);
      if (id != calendarId) {
        calendarId = id;
        _saveUi();
        _touch(); // other devices write into the same calendar
      }
      await google.sync(id, due, now: now);
      calendarProblem = null;
    } on NetworkError {
      return; // offline: the next refresh catches up
    } on Exception {
      calendarProblem = CalendarProblem.update; // tried again at the next refresh
    } finally {
      if (calendarProblem != before) notifyListeners();
    }
  }

  /// Off: the desktop forgets and revokes the calendar's refresh token; a
  /// phone only drops its access token, since the plugin can revoke the whole
  /// account alone, Drive with it. Drive's own grant is never touched.
  Future<void> _signOutCalendar(OAuthSignIn auth) async {
    try {
      await auth.signOut();
    } on Exception {
      return; // offline: the token is gone from this device all the same
    }
  }

  /// Settings' sign-in on a device where the calendar is on (another device
  /// turned it on) but this one has no grant yet.
  Future<void> signInCalendar() async {
    final auth = calendarAuth;
    if (auth == null) return;
    calendarProblem = null;
    try {
      await auth.signIn();
    } on Exception {
      calendarProblem = CalendarProblem.signIn;
      notifyListeners();
      return;
    }
    if (calendarNudge) calendarNudgeLater(); // taken: not offered again
    await refreshReminders(ask: false);
    notifyListeners();
  }

  /// Settings' Add to Google Calendar (#432): on, its own sign-in, then Google
  /// reminds on every device instead of this one; off, the coming events go
  /// and this device reminds again.
  Future<void> setCalendar(bool on) async {
    final auth = calendarAuth;
    if (auth == null || on == calendar || calendarBusy) return;
    calendarProblem = null;
    calendarBusy = true;
    notifyListeners();
    try {
      if (on && !await auth.signedIn()) await auth.signIn();
      if (!on && await auth.signedIn() && calendarId != null) {
        await calendarFor(auth).clear(calendarId!, now: clock().toLocal());
      }
    } on Exception {
      if (on) {
        calendarProblem = CalendarProblem.signIn;
        calendarBusy = false;
        notifyListeners();
        return; // still off: this device keeps reminding
      }
      // Off all the same; the events that could not go stay in that calendar.
    }
    if (!on) await _signOutCalendar(auth);
    calendar = on;
    _saveUi();
    _touch();
    await refreshReminders(ask: false);
    calendarBusy = false;
    notifyListeners();
  }

  /// Settings' Allow: asks for notifications again; whether they are allowed
  /// now. The system may no longer show its question (asked twice already).
  Future<bool> allowReminders() async {
    final device = reminders;
    if (device == null) return false;
    try {
      remindersAllowed = await device.ask();
    } on Exception {
      return false;
    } finally {
      notifyListeners();
    }
    await refreshReminders(ask: false);
    return remindersAllowed ?? false;
  }

  void _markSyncedNotes(SyncReport report) {
    for (final rel in [...report.pulled, ...report.merged, ...report.removedLocal]) {
      index.markChanged(p.joinAll([paths.notes.path, ...rel.split('/')]));
    }
  }

  static List<String>? _unresolved(Conflict conflict) => null;

  List<NoteInfo> listNotes() => (index..rebuild()).listNotes();

  /// The note file as it is on disk: what a Markdown export sends.
  String noteFile(NoteInfo note) =>
      File(notePath(paths.notes.path, note.kind, note.slug)).readAsStringSync();

  /// The PDF fonts, loaded on the first PDF export.
  late final Future<PdfFonts> _fonts = PdfFonts.load(rootBundle);

  /// [notes] as files in [format], handed to [exchange]; false when the
  /// person called it off.
  Future<bool> exportNotes(List<NoteInfo> notes, ExportFormat format) async {
    final files = await exportFiles(
      [for (final note in notes) (note.slug, noteFile(note))],
      format,
      fonts: await _fonts,
    );
    return exchange.send(files, subject: notes.length == 1 ? notes.single.title : 'Notelore');
  }

  /// Imports the files the person picks, each on its own: a note that is not
  /// one (or not text at all) is refused, the rest come in without
  /// overwriting anything. What happened to each, in order.
  Future<List<ImportReport>> importNotes() async {
    final picked = await exchange.pick();
    if (picked.isEmpty) return const [];
    final reports = await _exclusive(
      () async => [for (final file in picked) (file: file.name, imported: _import(file.bytes))],
    );
    const news = {ImportOutcome.added, ImportOutcome.renamed};
    final changed = reports.any((r) => news.contains(r.imported?.outcome));
    if (changed) {
      unawaited(refreshReminders(ask: false)); // a shared note's reminders come too
      notifyListeners();
      if (driveConnected) unawaited(syncNow());
    }
    return reports;
  }

  Imported? _import(List<int> bytes) {
    try {
      final imported = importNote(paths.notes.path, utf8.decode(bytes));
      if (imported.outcome != ImportOutcome.alreadyThere) index.markChanged(imported.path);
      return imported;
    } on FormatException {
      return null; // not UTF-8, or not a Notelore note
    }
  }

  /// Moves [note] under `_archive/<date>/`: nothing is ever hard-deleted. Returns
  /// where it went, for [restoreNote]; null when a sync or a chat turn already
  /// removed it. Queued, so it never races a sync.
  Future<String?> deleteNote(NoteInfo note) => _exclusive(() async {
    final path = notePath(paths.notes.path, note.kind, note.slug);
    if (!File(path).existsSync()) return null;
    final archived = archiveNote(paths.notes.path, path, today: today);
    index.markChanged(path);
    unawaited(
      refreshReminders(ask: false),
    ); // the calendar's network never holds up a delete (#504)
    notifyListeners();
    return archived;
  });

  /// What was archived, newest first.
  List<ArchivedNote> listArchived() => core.listArchived(paths.notes.path);

  /// An archived note's file as written.
  String readArchived(ArchivedNote archived) =>
      File(archived.path).readAsStringSync().replaceAll('\r\n', '\n');

  /// Puts [archived] back where it came from; false when a note took the name.
  Future<bool> restoreArchived(ArchivedNote archived) => _exclusive(() async {
    try {
      final path = core.restoreArchived(paths.notes.path, archived);
      index.markChanged(path);
    } on RestoreTaken {
      return false;
    }
    unawaited(refreshReminders(ask: false));
    notifyListeners();
    return true;
  });

  /// Deletes [archived] for good, at the person's own word (#438): only Drive's
  /// trash keeps it after the next sync. Its emptied folders go too.
  Future<void> deleteArchived(ArchivedNote archived) => _exclusive(() async {
    _deleteArchived(archived);
    notifyListeners();
    if (driveConnected) unawaited(syncNow());
  });

  /// Deletes the whole archive for good; how many notes went.
  Future<int> emptyArchive() => _exclusive(() async {
    final all = listArchived();
    all.forEach(_deleteArchived);
    notifyListeners();
    if (all.isNotEmpty && driveConnected) unawaited(syncNow());
    return all.length;
  });

  void _deleteArchived(ArchivedNote archived) {
    // Already gone (a sync, or by hand, since the list was drawn): nothing to do.
    if (File(archived.path).existsSync()) File(archived.path).deleteSync();
    removeEmptyFolders(p.dirname(archived.path), within: p.join(paths.notes.path, archiveFolder));
  }

  /// Undoes [deleteNote], unless a new note has taken the place meanwhile.
  Future<void> restoreNote(NoteInfo note, String archived) => _exclusive(() async {
    final path = notePath(paths.notes.path, note.kind, note.slug);
    if (File(path).existsSync()) return; // never overwrite; the archive copy stays
    moveWithRetry(archived, path);
    index.markChanged(path);
    unawaited(refreshReminders(ask: false));
    notifyListeners();
  });

  /// The note's file as written, for the reader to lay out (#426).
  /// CRLF (an editor on Windows may save one) reads like LF.
  String readNote(NoteInfo note) =>
      File(notePath(paths.notes.path, note.kind, note.slug))
          .readAsStringSync()
          .replaceAll('\r\n', '\n');

  var _disposed = false;

  /// A background sync may finish after the app closed the session.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    stopAutoSync();
    _stopRetrying();
    _disposed = true;
    index.close();
    unawaited(_freeDeviceEngine());
    super.dispose();
  }
}

String withoutFrontMatter(String text) {
  if (!text.startsWith('---\n')) return text;
  final end = text.indexOf('\n---\n', 3);
  return end < 0 ? text : text.substring(end + 5);
}
