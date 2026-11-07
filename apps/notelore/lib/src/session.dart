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
import 'package:notelore_core/notelore_core.dart'
    as core
    show aboutMeFacts, listArchived, restoreArchived;
import 'package:path/path.dart' as p;

import 'audio_file.dart';
import 'audio_native.dart';
import 'device_auth.dart';
import 'device_host.dart';
import 'device_model.dart';
import 'device_native.dart';
import 'lock_state.dart';
import 'pdf_native.dart';
import 'prefs.dart';
import 'quick_widget.dart' show QuickOpen;
import 'reminder_center.dart';
import 'reminder_notifier.dart';
import 'strings.dart';
import 'theme.dart';
import 'transfer.dart';
import 'voice.dart';
import 'whisper_model.dart';
import 'whisper_native.dart';
import 'whisper_speech.dart' show MicrophoneChoice, Transcriber;

export 'reminder_center.dart' show CalendarProblem, ReminderCenter;

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

/// [cards]: what an answer shows under its words (#791); empty on every other line.
typedef ChatLine = ({ChatRole role, String text, List<AnswerCard> cards});

/// What happened to one imported file: null when it was not a note.
typedef ImportReport = ({String file, Imported? imported});

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
    this.meteredNetwork = _unknownCost,
    this.retryEvery = const Duration(minutes: 1),
    this.every = Timer.periodic,
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

  /// Google Calendar's own grant (#432): another scope than Drive's, asked
  /// for when the switch is turned on; null in a build without Google sign-in.
  final OAuthSignIn? calendarAuth;
  final ReminderCalendar Function(OAuthSignIn auth) calendarFor;

  /// The reminders and the calendar (#659); what follows forwards to it.
  late final ReminderCenter reminderCenter = ReminderCenter(
    root: paths.notes.path,
    reminders: reminders,
    calendarAuth: calendarAuth,
    calendarFor: calendarFor,
    clock: clock,
    offThread: offThread,
    isPrivate: () => lock.enabled,
    hiddenText: () => strings.reminderHidden,
    actionLabels: () => (done: strings.reminderDone, snooze: strings.reminderSnooze),
    save: _saveUi,
    share: _touch,
  )..addListener(notifyListeners);

  bool? get remindersAllowed => reminderCenter.remindersAllowed;
  bool get calendar => reminderCenter.calendar;
  set calendar(bool on) => reminderCenter.calendar = on;
  String? get calendarId => reminderCenter.calendarId;
  set calendarId(String? id) => reminderCenter.calendarId = id;
  CalendarProblem? get calendarProblem => reminderCenter.calendarProblem;
  bool get calendarBusy => reminderCenter.calendarBusy;
  bool? get calendarHere => reminderCenter.calendarHere;
  bool get calendarNudge => reminderCenter.calendarNudge;
  void calendarNudgeLater() => reminderCenter.calendarNudgeLater();
  bool get calendarAvailable => calendarAuth != null;
  Future<void> refreshReminders({bool ask = true}) => reminderCenter.refreshReminders(ask: ask);
  Future<void> signInCalendar() => reminderCenter.signInCalendar();
  Future<void> setCalendar(bool on) => reminderCenter.setCalendar(on);
  Future<bool> allowReminders() => reminderCenter.allowReminders();

  /// The lock turned on or off: the notifications follow (#431).
  void _lockChanged() {
    notifyListeners();
    reminderCenter.lockChanged();
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

  /// Whether this device's connection costs by the byte (mobile data, a
  /// hotspot); null when that is not known.
  final Future<bool?> Function() meteredNetwork;
  static Future<bool?> _unknownCost() async => null;

  /// The device model's files from an app version before, which pinned
  /// another file: run until the pinned one is here, then deleted (#767).
  List<File> get _oldDeviceFiles {
    final dir = Directory(deviceModel.dir);
    if (!dir.existsSync()) return const [];
    final pinned = {for (final file in deviceFiles) file.name};
    return [
      for (final file in dir.listSync().whereType<File>())
        if (RegExp(r'\.gguf(\.part)?$').hasMatch(file.path) &&
            !pinned.contains(p.basename(file.path).replaceFirst(RegExp(r'\.part$'), '')))
          file,
    ];
  }

  String get _deviceFile => switch (_oldDeviceFiles.where((f) => f.path.endsWith('.gguf'))) {
    final old when old.isNotEmpty && !deviceModel.ready => p.basename(old.first.path),
    _ => deviceFiles.first.name,
  };

  /// A file Windows still holds (antivirus, an indexer) stays: the next start tries again.
  Future<void> _dropOldDeviceFiles() => Future.wait([
    for (final old in _oldDeviceFiles) old.delete().then<void>((_) {}, onError: (Object _) {}),
  ]);

  /// Where a new device model from an app update stands; null when there is
  /// none, or the person put its notice away.
  DeviceUpdate? deviceUpdate;

  /// What the new device model costs to download.
  int get deviceUpdateBytes => deviceModel.bytes;

  /// The model on the device is in use and its pinned file is not here: on
  /// Wi-Fi it downloads by itself, on a connection that costs (or one not
  /// known) the person is asked first.
  Future<void> _checkDeviceModel() async {
    if (deviceModel.ready) return deviceUpdating = _dropOldDeviceFiles();
    if (spec?.access != ProviderAccess.deviceFile) return;
    if (await meteredNetwork() == false) return updateDeviceModel();
    deviceUpdate = DeviceUpdate.ask;
    notifyListeners();
  }

  /// Downloads the pinned device model while the chat goes on with the old
  /// one, then moves to it between turns and deletes the old file. A failed
  /// download keeps the old file; the next start tries again.
  Future<void> updateDeviceModel() => deviceUpdating = _updateDeviceModel();

  /// The update running or last run, for a test to wait on.
  @visibleForTesting
  Future<void>? deviceUpdating;

  Future<void> _updateDeviceModel() async {
    deviceUpdate = DeviceUpdate.downloading;
    notifyListeners();
    await device.download();
    if (!deviceModel.ready) {
      deviceUpdate = DeviceUpdate.failed;
      notifyListeners();
      return;
    }
    await _exclusive(() async {
      await device.free();
      await _dropOldDeviceFiles();
      if (spec case final spec? when spec.access == ProviderAccess.deviceFile) {
        _use(spec, '', model!);
      }
    });
    deviceUpdate = DeviceUpdate.done;
    notifyListeners();
  }

  void dismissDeviceUpdate() {
    deviceUpdate = null;
    notifyListeners();
  }

  /// The engine that runs [deviceModel]'s file: llama.cpp; a fake in tests.
  final LocalEngine Function(String path) makeDeviceEngine;

  /// [chosen]'s provider: the model on the device runs on the one engine.
  LlmProvider _providerFor(ProviderSpec chosen, String key, String chosenModel) {
    if (chosen.access == ProviderAccess.deviceFile) return device.provider(chosenModel);
    return makeProvider(
      chosen,
      key,
      model: chosenModel,
      planToken: chosen.access == ProviderAccess.signIn ? chatGpt!.token : null,
      webSearch: webSearch && chosen.webSearch,
    );
  }

  /// The model on the device (#328): its one engine, its prefill and its
  /// download (#659); what follows forwards to it.
  late final DeviceModelHost device = DeviceModelHost(
    model: deviceModel,
    file: () => _deviceFile,
    makeEngine: makeDeviceEngine,
    exclusive: _exclusive,
    fetch: (progress, problem) => _fetch(deviceModel, progress, problem),
  )..addListener(notifyListeners);

  /// The model is loading and reading its fixed prompt, before any message:
  /// the chat says so while it runs.
  bool get preparing => device.preparing;

  /// From 0 to 1 while the device model downloads, else null.
  double? get deviceProgress => device.progress;

  /// Why the last device model download failed, if it did.
  DownloadProblem? get deviceProblem => device.problem;

  /// One download at a time; a second call waits for the one running.
  Future<void> downloadDeviceModel() => device.download();

  /// Skipped while the setup wizard is testing the model: that test turn has
  /// another prompt and would replace the cache just filled.
  void _startDevicePrefill() {
    if (!finishingSetup) device.startPrefill(slimSystemPrompt(today), slimTools);
  }

  /// The model on the device is offered (where llama.cpp runs: Android,
  /// Windows, macOS).
  final bool deviceModels;

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

  /// Removes an original kept for a message that never reached the model, and
  /// the marker that pointed at it, so a retry cannot link a missing file.
  void discardOriginal(String rel) {
    if (!rel.startsWith('$attachmentsFolder/') ||
        rel
            .split('/')
            .any((part) => part.isEmpty || part == '.' || part == '..' || part.contains(r'\'))) {
      return;
    }
    final marker = ' original="$rel"';
    for (var i = 0; i < transcript.length; i++) {
      final line = transcript[i];
      if (line.role == ChatRole.assistant || !line.text.contains(marker)) continue;
      transcript[i] = (role: line.role, text: line.text.replaceAll(marker, ''), cards: line.cards);
    }
    try {
      File(p.joinAll([paths.notes.path, ...rel.split('/')])).deleteSync();
    } on FileSystemException {
      // Already gone, or held: the marker is gone either way.
    }
    notifyListeners();
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
  DownloadProblem? whisperProblem;

  Future<void> downloadWhisper() async {
    if (whisperProgress != null) return;
    await _fetch(whisper, (done) => whisperProgress = done, (why) => whisperProblem = why);
  }

  /// Downloads [model], telling [progress] (null when over) and [problem].
  Future<void> _fetch(
    WhisperModel model,
    void Function(double? done) progress,
    void Function(DownloadProblem? why) problem,
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
      // Said in plain words; the detail only in a debug build's log.
      if (kDebugMode) debugPrint('Model download failed: $error');
      problem(downloadProblem(error));
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

  /// The about-me facts go to cloud models too; a model on this machine always gets them.
  bool aboutMeToCloud = true;

  /// The model in use may keep about-me facts from the chat.
  bool get chatKeepsFacts => _agent?.aboutMe ?? false;

  /// Turns sending the about-me facts to cloud models on or off; after a running turn.
  Future<void> setAboutMeToCloud(bool on) => _exclusive(() async {
    await _applyAboutMeToCloud(on);
    _touch();
  });

  Future<void> _applyAboutMeToCloud(bool on) async {
    aboutMeToCloud = on;
    _saveUi();
    if (model case final current?) await _applyModel(current);
  }

  /// Off wins: a stale "on" from a device that has not caught up never sends the facts.
  Future<void> _adoptAboutMeToCloud(Object? theirs) async {
    if (theirs == false && aboutMeToCloud) await _applyAboutMeToCloud(false);
  }

  /// What the person told about themselves, one fact a line.
  List<String> aboutMeFacts() => aboutMe(paths.notes.path);

  /// Each fact with its section, in the file's order (#671).
  List<({String section, String fact})> aboutMeEntries() => core.aboutMeFacts(paths.notes.path);

  /// Adds [fact] to [section], a new heading in the app's language; throws
  /// [ArgumentError] when it is empty or already there.
  Future<void> rememberFact(String fact, {String section = 'other'}) => _aboutMe(
    () => rememberAboutMe(paths.notes.path, fact, section: section, lang: strings.languageCode),
  );

  /// Replaces [old] with [fact], moved to [section] when given; throws
  /// [ArgumentError] when [old] is gone or [fact] is taken.
  Future<void> updateFact(String old, String fact, {String? section}) => _aboutMe(
    () => updateAboutMe(paths.notes.path, old, fact, section: section, lang: strings.languageCode),
  );

  /// Removes [fact]; throws [ArgumentError] when it is gone.
  Future<void> forgetFact(String fact) => _aboutMe(() => forgetAboutMe(paths.notes.path, fact));

  // Refused or not, the screens reread: a refusal often means another device changed it.
  Future<void> _aboutMe(void Function() change) => _exclusive(() async {
    try {
      change();
    } finally {
      notifyListeners();
    }
  });

  /// Whether the model's turns are at hand for [reportWrong]; a switch to a
  /// cloud model drops what a local one was told.
  bool get canReport => _agent?.messages.isNotEmpty ?? false;

  /// Keeps the newest turn as feedback for the model's training (#753), in the
  /// notes folder so it syncs; its path relative to the notes.
  Future<String> reportWrong(String expected) => _exclusive(() async {
    final rel = reported = saveFeedback(
      paths.notes.path,
      _agent!.messages,
      model: '${spec!.name} $model',
      expected: expected,
      now: clock(),
    );
    notifyListeners();
    return rel;
  });

  /// The newest answer's report, until it is taken back or the next message goes.
  String? reported;

  /// Undoes [reportWrong].
  Future<void> takeBackFeedback(String rel) => _exclusive(() async {
    // Both the snackbar's Undo and the filled button take it back; the second finds it gone.
    final file = File(p.joinAll([paths.notes.path, ...rel.split('/')]));
    if (file.existsSync()) file.deleteSync();
    if (reported == rel) reported = null;
    notifyListeners();
  });

  /// The language the user picked in Settings; the device's by default.
  AppLanguage language = AppLanguage.system;

  /// The look: light, dark or the device's.
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

  void setAppearance(Appearance chosen) {
    _applyAppearance(chosen);
    _touch();
  }

  void _applyAppearance(Appearance chosen) {
    appearance = chosen;
    _saveUi();
  }

  /// The chat's own text sizes, on top of the device's; 100% is the default.
  static const chatTextSteps = <double>[0.85, 1.0, 1.15, 1.3, 1.5];
  static const chatTextDefault = 1;

  /// The step picked on this device; never synced to another one.
  int chatTextStep = chatTextDefault;

  double get chatTextScale => chatTextSteps[chatTextStep];

  void zoomChatIn() => setChatTextStep(chatTextStep + 1);

  void zoomChatOut() => setChatTextStep(chatTextStep - 1);

  void resetChatText() => setChatTextStep(chatTextDefault);

  void setChatTextStep(int step) {
    final next = step.clamp(0, chatTextSteps.length - 1);
    if (next == chatTextStep) return;
    chatTextStep = next;
    _saveUi();
  }

  /// The Sunday whose look back was closed here, as an ISO date, never synced.
  String? lookBackClosed;

  void closeLookBack(String sunday) {
    lookBackClosed = sunday;
    _saveUi();
  }

  /// Announces the language and look, and remembers them on this device.
  void _saveUi() {
    notifyListeners();
    try {
      atomicWrite(
        _ui,
        jsonEncode({
          ..._shared.toJson(),
          if (reminderCenter.dropCalendars.isNotEmpty)
            'dropCalendars': reminderCenter.dropCalendars,
          'microphone': ?microphone,
          if (setUpBefore) 'setUp': true,
          if (chatTextStep != chatTextDefault) 'chatTextStep': chatTextStep,
          if (reminderCenter.calendarNudged) 'calendarNudged': true,
          'lookBackClosed': ?lookBackClosed,
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
      final shared = SharedPrefs.fromJson(saved);
      language = shared.language ?? AppLanguage.system;
      appearance = shared.appearance ?? Appearance.system;
      webSearch = shared.webSearch ?? true;
      aboutMeToCloud = shared.aboutMeToCloud ?? true;
      calendar = shared.calendar ?? false;
      calendarId = shared.calendarId;
      reminderCenter.calendarNudged = saved['calendarNudged'] == true;
      reminderCenter.dropCalendars
        ..clear()
        ..addAll((saved['dropCalendars'] as List? ?? const []).whereType<String>());
      setUpBefore = saved['setUp'] == true;
      chatTextStep = switch (saved['chatTextStep']) {
        final int step when step >= 0 && step < chatTextSteps.length => step,
        _ => chatTextDefault,
      };
      microphone = switch (saved['microphone']) {
        final String id => id,
        _ => null,
      };
      lookBackClosed = switch (saved['lookBackClosed']) {
        final String day => day,
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
      if (switch (spec.access) {
        ProviderAccess.signIn => chatGpt != null,
        ProviderAccess.apiKey => true,
        ProviderAccess.localMark => localModels,
        ProviderAccess.deviceFile => deviceModels,
      })
        spec,
  ];

  /// Models running on this machine (Ollama) are offered: not on a phone.
  final bool localModels;

  /// How often messages that wait are tried again by themselves.
  final Duration retryEvery;

  /// The periodic timer that tries them; tests tick it by hand.
  final Timer Function(Duration period, void Function(Timer) onTick) every;

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

  Remote? _remote;
  var driveConnected = false;
  var _pendingSyncs = 0;

  /// A sync is running or queued.
  bool get syncing => _pendingSyncs > 0;

  /// What the last sync did, for the settings screen; null before any.
  String? syncStatus;

  /// When a sync last finished cleanly, and whether the last one failed
  /// (#774). The main screens show one of them.
  DateTime? lastSynced;
  var syncFailed = false;

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

  /// The answer or failure a turn just added, for a screen reader to hear
  /// once; the chat takes it. Never a line loaded from history.
  ChatLine? fresh;

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

  /// What a tap on the home-screen widget asked for (#799), until a screen takes it.
  QuickOpen? quickOpen;

  void openQuick(QuickOpen open) {
    quickOpen = open;
    notifyListeners();
  }

  bool busy = false;

  bool get ready => _agent != null;

  /// The system prompt of the wizard's one test turn (#361).
  static const trySystem = 'You are Notelore. Reply in one short sentence, in the language asked.';

  /// One real turn with the connected model, no tools and no notes: the answer
  /// shows the user it works. It costs a few tokens, as the wizard says.
  Future<String> tryModel() async {
    final device = this.device.loaded;
    if (device) {
      this.device.cancelPrefill();
      await _queue; // a prefill already under way ends before the test prompt
    }
    try {
      // Not metered: a few tokens to say hello are not the conversation's use.
      final provider = switch (_provider!) {
        MeteredProvider(:final provider) => provider,
        final other => other,
      };
      final answer = await provider.turn(trySystem, [
        {'role': 'user', 'content': strings.tryPrompt},
      ], const []);
      return answer.content.map((b) => b['text'] ?? '').join().trim();
    } finally {
      if (device) {
        _startDevicePrefill(); // the test prompt is not the chat's
        notifyListeners();
      }
    }
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
    _startDevicePrefill();
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
    unawaited(_checkDeviceModel());
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
      if (found.access == ProviderAccess.signIn && !(await chatGpt?.signedIn() ?? false)) return;
      if (found.access == ProviderAccess.localMark) await _markOllama(found);
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
      if (spec.access == ProviderAccess.signIn
          ? await chatGpt!.signedIn()
          : await keys.read(key: _keyName(spec)) != null)
        spec,
  ];

  /// Back to a connected model with its stored key, checked again; never opens
  /// a browser. Throws [StateError] when it is not connected (any more).
  Future<void> switchTo(ProviderSpec spec) async {
    final key = spec.access == ProviderAccess.signIn ? '' : await keys.read(key: _keyName(spec));
    if (key == null) throw StateError('${spec.displayName} is not connected');
    await _connect(spec, key, signIn: false);
  }

  /// Forgets one model's key or sign-in. The active one leaves no model until
  /// another is chosen; the notes and the conversation stay.
  Future<void> disconnect(ProviderSpec spec) async {
    if (spec.access == ProviderAccess.signIn) {
      await chatGpt?.signOut();
    } else {
      await keys.delete(key: _keyName(spec));
    }
    if (spec.access == ProviderAccess.deviceFile) {
      // Removed means removed: its 2.5 GB go too (downloaded again on request),
      // once a download that runs has ended, so it never writes into nothing.
      await device.downloading;
      await device.free();
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
    final keyed = spec.access != ProviderAccess.signIn;
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
    if (spec.access == ProviderAccess.signIn &&
        await keys.read(key: '$keySpace.chatgpt.welcomed') == null) {
      showPlanWelcome = true;
      await keys.write(key: '$keySpace.chatgpt.welcomed', value: 'yes');
    }
    _use(spec, trimmed, chosen);
  }

  /// The models [spec] offers. A key is checked by listing them; the ChatGPT
  /// plan signs in first when [signIn] (only on connect: a refresh never opens
  /// a browser).
  Future<List<String>> _models(ProviderSpec spec, String key, {required bool signIn}) async =>
      switch (spec.access) {
        // Its one model, once its file is here; nothing to ask a server.
        ProviderAccess.deviceFile
            when !deviceModel.ready && _deviceFile == deviceFiles.first.name =>
          throw const TransientValidationError('Download the model first'),
        ProviderAccess.deviceFile => [spec.defaultModel],
        ProviderAccess.apiKey ||
        ProviderAccess.localMark => currentModels(spec.name, await validate(spec, key)),
        ProviderAccess.signIn => currentModels(spec.name, await _planModels(signIn: signIn)),
      };

  Future<List<String>> _planModels({required bool signIn}) async {
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

  /// The model a blank choice goes back to: the one [_startModel] picks, else
  /// the provider's fixed default.
  String get defaultModel {
    final current = spec!;
    return _startModel(current, models) ?? current.defaultModel;
  }

  /// Nothing listed to start on: the fixed default, but never for Ollama, which
  /// can only talk with a model it has (#471).
  static String _fallback(ProviderSpec spec) => switch (spec) {
    ProviderSpec(id: ProviderId.ollama) => throw const NoLocalModel(),
    ProviderSpec(:final defaultModel) when defaultModel.isNotEmpty => defaultModel,
    _ => throw TransientValidationError('${spec.displayName} lists no models'),
  };

  /// Which of [listed] a provider starts on. Ollama: one that is installed,
  /// Notelore's own first (#471). Gemini: its default when listed, the model a
  /// free AI Studio key has quota for; the cheapest listed is often a lite or
  /// preview one with none (#400). Any other: the cheapest listed.
  static String? _startModel(ProviderSpec spec, List<String> listed) => switch (spec.id) {
    ProviderId.ollama => ollamaStartModel(listed),
    ProviderId.device => null,
    ProviderId.gemini when listed.contains(spec.defaultModel) => spec.defaultModel,
    ProviderId.chatgpt ||
    ProviderId.anthropic ||
    ProviderId.openai ||
    ProviderId.gemini ||
    ProviderId.deepseek => cheapestModel(spec.name, listed),
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
    unawaited(device.free());
  }

  /// Forgets every provider's key on this device and the chosen provider; the
  /// notes stay.
  Future<void> logout() async {
    _outbox.clear(); // dropped with the conversation, never run against another login
    _saveQueue();
    _stopRetrying();
    for (final spec in providerSpecs.where((s) => s.access != ProviderAccess.signIn)) {
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
    final wasLocal = spec != null && onThisMachine(spec!, model ?? '');
    spec = chosen;
    model = chosenModel;
    if (chosen.access != ProviderAccess.deviceFile) unawaited(device.free());
    final toolbox = Toolbox(paths.notes.path, index, today: today);
    _provider = MeteredProvider(_providerFor(chosen, key, chosenModel), chosen.name, usage);
    final me = aboutMeToCloud || onThisMachine(chosen, chosenModel);
    // A model switch keeps the conversation (logout has already dropped it), except
    // what a local model was told about the person, on its way to a cloud one.
    final history = wasLocal && _agent?.aboutMe == true && !me
        ? const <Message>[]
        : _agent?.messages ?? const <Message>[];
    _agent = Agent(
      _provider!,
      toolbox,
      today: today,
      timing: timing,
      slim:
          chosen.access ==
          ProviderAccess.deviceFile, // every token is read on the phone first (#447)
      aboutMe: me,
    )..messages.addAll(history);
    _startDevicePrefill();
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

  /// The model takes images with a message (#278): if the provider's does.
  bool get acceptsImages => spec?.takesImages(model ?? '') ?? false;

  /// The images of the last message, for [resend]; only ever in memory.
  var _lastImages = const <Block>[];

  /// One chat turn, then a sync. A provider failure becomes an error line; the
  /// agent has already taken the turn back, so the user can simply send again.
  /// Sent while a turn runs, a message joins that turn instead (see [_later]).
  /// [images] go with this turn only, never into the queue or a saved file:
  /// the chat sends them only when nothing runs or waits ([acceptsImages]).
  /// Returns whether the turn delivered an answer or wrote notes; a failed
  /// image send returns false so the caller can drop its kept original.
  Future<bool> send(String text, {List<Block> images = const []}) async {
    final message = text.trim();
    // No model to answer (#363): the chat asks for one; nothing to send with.
    if (message.isEmpty || !ready) return false;
    // Images never join a running turn or the queue: there is no copy to keep.
    if (images.isNotEmpty && (_outbox.isNotEmpty || busy)) return false;
    _lastImages = images;
    // Behind a waiting message, a new one waits too (kept, in order), even while
    // the waiting ones are being tried.
    if (_outbox.isNotEmpty) {
      _enqueue(message);
      await retryNow();
      return false;
    }
    transcript.add((role: ChatRole.user, text: message, cards: const []));
    reported = null;
    if (busy) {
      _later.add(message); // joins the running turn at its next step
      notifyListeners();
      return false;
    }
    return _turns(message, images: images);
  }

  /// Turns until nothing written meanwhile is left; busy throughout. [images]
  /// go with the first.
  Future<bool> _turns(String first, {bool queued = false, List<Block> images = const []}) async {
    busy = true;
    _halted = false;
    notifyListeners();
    var delivered = true;
    var firstTurn = true;
    String? message = first;
    var fromQueue = queued;
    var pictures = images;
    while (message != null) {
      _stopped = false; // before the queue: a Stop while it waits behind a sync still counts
      final (current, wasQueued, withImages) = (message, fromQueue, pictures);
      final waiting = Stopwatch()..start();
      final turnDelivered = await _exclusive(() {
        timing?.call('queue ${waiting.elapsedMilliseconds} ms');
        return _turn(current, queued: wasQueued, images: withImages);
      });
      if (firstTurn) {
        delivered = turnDelivered; // only this message's turn owns its image original
        firstTurn = false;
      }
      (message, fromQueue) = _next();
      pictures = const [];
    }
    busy = false;
    notifyListeners();
    if (driveConnected) unawaited(syncNow());
    return delivered;
  }

  /// The next message to run and whether it comes from the queue: none once
  /// one had to wait (the rest waits behind it).
  (String?, bool) _next() {
    if (_halted) return (null, false);
    if (_outbox.isNotEmpty) return (_outbox.first, true);
    return (_rest(), false);
  }

  /// One chat turn: the answer, or what its failure means.
  Future<bool> _turn(String message, {required bool queued, required List<Block> images}) async {
    final taken = <String>[];
    Agent? asked; // the one that ran the turn, even if a logout replaced it since
    // For the usage page (#481): counts only, never a word of the turn.
    final watch = Stopwatch()..start();
    final metered = _provider;
    var before = 0;
    var toolCalls = 0;
    var failed = false;
    var delivered = false;
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
      delivered = true;
      toolCalls = _toolCalls(asked.messages.skip(before));
      transcript.add(
        fresh = (role: ChatRole.assistant, text: strings.core(answer), cards: asked.cards),
      );
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
    return delivered || (asked?.wroteNotes ?? false);
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
    transcript.add(
      fresh = (
        role: ChatRole.error,
        text: [
          strings.chatError(error),
          if (wrote) strings.notesMayBeSaved,
          if (later && images) strings.imagesCannotWait,
        ].join('\n\n'),
        cards: const [],
      ),
    );
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
    final ChatLine line = (role: ChatRole.pending, text: message, cards: const []);
    at < 0 ? transcript.add(line) : transcript[at] = line;
    _saveQueue();
    _startRetrying();
    notifyListeners();
  }

  void _startRetrying() => _retry ??= every(retryEvery, (_) => unawaited(retryNow()));

  /// The first waiting [message] reached the model.
  void _sent(String message) {
    // Logged out meanwhile: the queue went with the conversation.
    if (_outbox.firstOrNull != message) return;
    _outbox.removeAt(0);
    final at = transcript.indexWhere((l) => l.role == ChatRole.pending && l.text == message);
    if (at >= 0) transcript[at] = (role: ChatRole.user, text: message, cards: const []);
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
        transcript.add((role: ChatRole.pending, text: message, cards: const []));
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
    lastSynced = null;
    syncFailed = false;
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
      ..._shared.toJson(),
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

  /// This device's values of the settings every device shares (#662).
  SharedPrefs get _shared => SharedPrefs(
    language: language,
    appearance: appearance,
    webSearch: webSearch,
    aboutMeToCloud: aboutMeToCloud,
    calendar: calendar,
    calendarId: calendarId,
  );

  /// Another device's settings. Its provider only when this device can use it
  /// without asking (a key, or the ChatGPT sign-in); Ollama is local to each machine.
  Future<void> _adopt(Map<String, Object?> theirs) async {
    final shared = SharedPrefs.fromJson(theirs);
    if (shared.language case final l?) _applyLanguage(l);
    _applyAppearance(shared.appearance ?? appearance);
    if (shared.webSearch case final on? when on != webSearch) await _applyWebSearch(on);
    await _adoptAboutMeToCloud(theirs['aboutMeToCloud']);
    if (shared.calendar case final on?) reminderCenter.adopt(on, shared.calendarId);
    await _adoptProvider(theirs['provider'], theirs['model']);
  }

  /// Another device's provider and model, when this device can use it without asking.
  Future<void> _adoptProvider(Object? name, Object? chosen) async {
    // A local model is this machine's own: another device's choice of one stays there.
    if (name is! String || chosen is! String) return;
    final found = providerSpecs.where((s) => s.name == name && !s.local).firstOrNull;
    if (found == null) return;
    if (found == spec) {
      if (chosen != model) await _applyModel(chosen);
      return;
    }
    final key = found.requiresApiKey ? await keys.read(key: _keyName(found)) : '';
    if (key == null) return;
    if (found.access == ProviderAccess.signIn && !(await chatGpt?.signedIn() ?? false)) return;
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
        lastSynced = clock().toUtc();
        syncFailed = false;
      } on MissingDriveGrant catch (error) {
        syncFailed = true;
        _needSignIn(strings.drivePermissionAgain, error.message);
      } on NotSignedIn catch (error) {
        syncFailed = true;
        _needSignIn(strings.signedOutOfGoogle, error.message);
      } on NetworkError {
        syncFailed = true;
        syncStatus = strings.offline;
      } on HttpError catch (error) {
        syncFailed = true;
        _driveFailed(error);
      } on FileSystemException catch (error) {
        // Windows: antivirus or an editor holds a note past the store's retries.
        syncFailed = true;
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

  void _markSyncedNotes(SyncReport report) {
    for (final rel in [...report.pulled, ...report.merged, ...report.removedLocal]) {
      index.markChanged(p.joinAll([paths.notes.path, ...rel.split('/')]));
    }
  }

  static List<String>? _unresolved(Conflict conflict) => null;

  List<NoteInfo> listNotes() => (index..rebuild()).listNotes();

  /// The Notes list's kind and tag filters; here so they outlive the screen
  /// while the app runs, and never saved.
  String? notesKind;
  String? notesTag;

  /// Of [notes], those with every word of [query] in their title or their
  /// words, folded like the index's search; the line that matched stands in
  /// for the newest words, unless only the title did.
  List<NoteInfo> findNotes(String query, List<NoteInfo> notes) {
    final found = index.notesWith(query);
    return [
      for (final note in notes)
        if (found.containsKey((note.kind, note.slug)))
          NoteInfo(
            note.slug,
            note.kind,
            note.title,
            note.updated,
            pinned: note.pinned,
            excerpt: found[(note.kind, note.slug)] ?? note.excerpt,
            tags: note.tags,
            openTodos: note.openTodos,
          ),
    ];
  }

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

  /// Completes or reopens todo [number] in [note] (#512); false when the note
  /// is gone since the screen drew it.
  Future<bool> setTodoDone(NoteInfo note, int number, {required bool done, String? text}) =>
      _exclusive(() async {
        final path = notePath(paths.notes.path, note.kind, note.slug);
        if (!File(path).existsSync()) return false;
        try {
          if (done) {
            completeTodo(path, number, today: today, expect: text);
          } else {
            reopenTodo(path, number, today: today, expect: text);
          }
        } on RangeError {
          return false; // moved or gone since the screen drew it
        }
        index.markChanged(path);
        notifyListeners();
        return true;
      });

  /// Pins [note] to the top of the list or unpins it; false when it is gone.
  Future<bool> pinNote(NoteInfo note, {required bool pinned}) => _exclusive(() async {
    final path = notePath(paths.notes.path, note.kind, note.slug);
    if (!File(path).existsSync()) return false;
    try {
      setPinned(path, pinned: pinned);
    } on ArgumentError {
      // Already so: a sync or the assistant got there first.
    }
    index.markChanged(path);
    notifyListeners();
    return true;
  });

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
    unawaited(device.free());
    device.dispose();
    super.dispose();
  }
}

String withoutFrontMatter(String text) {
  if (!text.startsWith('---\n')) return text;
  final end = text.indexOf('\n---\n', 3);
  return end < 0 ? text : text.substring(end + 5);
}

/// Whether [provider]'s [model] runs on this machine: the device model, or
/// Ollama on a loopback [host] with a model it does not forward to ollama.com.
bool onThisMachine(ProviderSpec provider, String model, {String? host}) {
  if (provider.access == ProviderAccess.deviceFile) return true;
  if (provider.access != ProviderAccess.localMark || RegExp(r'[:-]cloud$').hasMatch(model)) {
    return false;
  }
  final at = host ?? ollamaHost();
  final name = Uri.tryParse(at.contains('://') ? at : 'http://$at')?.host ?? '';
  return name == 'localhost' || name == '::1' || name == '0.0.0.0' || name.startsWith('127.');
}

/// A new device model from an app update: asked for, downloading, failed (the
/// old one stays), or done.
enum DeviceUpdate { ask, downloading, failed, done }
