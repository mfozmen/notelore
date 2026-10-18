import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notelore/src/device_auth.dart';
import 'package:notelore/src/drive_auth.dart' show Awake;
import 'package:notelore/src/reminder_notifier.dart';
import 'package:notelore/src/session.dart';
import 'package:notelore/src/transfer.dart';
import 'package:notelore/src/voice.dart';
import 'package:notelore/src/whisper_model.dart';
import 'package:notelore/src/whisper_speech.dart' show Transcriber;
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:share_plus/share_plus.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

final today = DateTime.utc(2026, 9, 30);

/// Returns the scripted answers in order and records the user messages it saw.
class ScriptedProvider implements LlmProvider {
  ScriptedProvider(this.answers, {this.model = 'scripted'});

  // AgentResponse, String (a text answer), an Exception, or a Future (e.g. one never answered)
  final List<Object> answers;

  /// The answer to the wizard's test turn (#361): a String, an Exception, or
  /// a Future of a String (one on its way).
  Object tryAnswer = 'Ready.';
  final asked = <String>[];

  /// How many messages of history each turn carried.
  final lengths = <int>[];

  @override
  final String model;

  @override
  Future<AgentResponse> turn(String system, List<Message> messages, List<Tool> tools) async {
    if (system == Session.trySystem) {
      final text = switch (tryAnswer) {
        final Exception error => throw error,
        final Error error => throw error,
        final Future<String> later => await later,
        final other => '$other',
      };
      return AgentResponse([
        {'type': 'text', 'text': text},
      ], 'end_turn');
    }
    asked.add('${messages.last['content']}');
    lengths.add(messages.length);
    final answer = answers.removeAt(0);
    if (answer is Exception) throw answer;
    if (answer is Future<AgentResponse>) return answer;
    if (answer is String) {
      return AgentResponse([
        {'type': 'text', 'text': answer},
      ], 'end_turn');
    }
    return answer as AgentResponse;
  }
}

/// Pumps until [done], letting real work finish between frames: the test clock
/// is fake, the disk and a real timer are not. It waits as long as a busy
/// machine needs, never a fixed few milliseconds, and fails after [timeout] of
/// real time only if the work is truly stuck (#365).
Future<void> settleUntil(
  WidgetTester tester,
  bool Function() done, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final waited = Stopwatch()..start(); // real time: the fake clock never moves on its own
  while (!done()) {
    if (waited.elapsed > timeout) fail('still not done after $timeout of real time');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// Everything a session test needs: temp folders, an empty keystore and a
/// provider that answers from [answers]. Validation passes unless [rejected].
class Harness {
  /// What the PDF reader finds in a PDF's bytes.
  Future<String> Function(Uint8List bytes) pdfText = (_) async => '';

  Harness({
    List<Object> answers = const [],
    this.rejected,
    this.auth,
    this.chatGpt,
    this.localModels = true,
    MemoryRemote? remote,
  }) : remote = remote ?? MemoryRemote() {
    final dir = Directory.systemTemp.createTempSync('notelore_app_');
    addTearDown(() => dir.deleteSync(recursive: true));
    paths = NotelorePaths(
      notes: Directory(p.join(dir.path, 'notes')),
      state: Directory(p.join(dir.path, 'state')),
    );
    provider = ScriptedProvider([...answers]);
    FlutterSecureStorage.setMockInitialValues({});
    FileSelectorPlatform.instance = files;
    scratch = Directory(p.join(dir.path, 'scratch'))..createSync();
  }

  /// Where exports go: the share sheet on a phone (the default here), save and
  /// open dialogs on the desktop.
  var mobile = true;
  final share = FakeShare();

  /// The device's notifications for reminders (#431).
  final reminders = FakeReminders();

  /// The device's own lock (#295): it answers as a test tells it.
  final deviceAuth = FakeDeviceAuth();
  final files = FakeFileSelector();
  late final Directory scratch;

  late final NotelorePaths paths;
  late final ScriptedProvider provider;

  /// When set, the provider refuses the key (tests may set it after connecting).
  Exception? rejected;

  /// When set, checking a key waits for it.
  Completer<void>? connectHold;

  /// What the provider lists for a good key; tests change it between calls.
  var models = <String>['claude-sonnet-5-5', 'model-a', 'model-b'];
  final FakeAuth? auth;

  /// The Drive folder; two harnesses can share one, like two devices.
  final MemoryRemote remote;
  final created = <(String, String?, String?)>[];

  /// Whether each provider was built with web search.
  final searches = <bool>[];

  /// The plan token each provider was built with (null for key providers).
  final tokens = <BearerToken?>[];

  /// The ChatGPT sign-in; none on phones.
  final FakeAuth? chatGpt;

  /// Whether Ollama is offered: the desktop's; false is a phone.
  final bool localModels;

  /// Voice mode's ears and mouth: nothing heard unless a test scripts it.
  final speech = FakeSpeech([]);
  final voice = FakeVoice();

  /// Whisper hearing an attached audio file (#285): its answers, in order.
  final fileTranscriber = FakeTranscriber();

  /// The platform's audio decoder for what is not WAV: none, unless a test sets one.
  Future<Float32List?> Function(Uint8List bytes) decodeAudio = (_) async => null;

  /// Whisper's speech, and the one small model file it downloads (absent: 404).
  final whisper = FakeSpeech([]);

  /// The microphones the device lists, and how Whisper asks which one is chosen.
  var microphones = <({String id, String label})>[];
  String? Function()? chosenMicrophone;
  String? modelPage; // not served unless a test sets it
  static final whisperFiles = [
    ModelFile(
      'w.onnx',
      'https://models.test/w.onnx',
      sha256.convert(utf8.encode('whisper bytes')).toString(),
      13,
    ),
  ];

  /// Thrown by the model download instead of an answer (an Error, say).
  Object? modelFailure;

  /// When set, the model is served only once it completes: a download that
  /// takes as long as a busy machine makes it (#365).
  Future<void>? modelGate;

  /// Web pages by URL, for links in a message (#211); a Future answers later.
  final pages = <String, FutureOr<String>>{};

  http.Client _models() => MockClient((request) async {
    if (pages[request.url.toString()] case final page?) {
      return http.Response(await page, 200, headers: {'content-type': 'text/html'});
    }
    if (modelFailure case final failure?) throw failure;
    await modelGate;
    if (modelPage case final page?) return http.Response(page, 200);
    return http.Response('', 404);
  });

  /// What the ChatGPT plan lists.
  var planModels = <String>['gpt-plan-a', 'gpt-plan-b'];

  /// A session the test closes itself; pass [owned] false when an app takes it over.
  Session session({
    bool owned = true,
    String systemLanguage = 'en',
    String keySpace = 'notelore',
    DateTime Function()? clock,
    Duration Function()? uptime,
    Duration retryEvery = const Duration(hours: 1), // tests try again by hand
    void Function(String entry)? timing,
    bool reminders = true,
  }) {
    final session = Session(
      paths,
      reminders: reminders ? this.reminders : null,
      timing: timing,
      retryEvery: retryEvery,
      systemLanguage: systemLanguage,
      keySpace: keySpace,
      clock: clock,
      uptime: uptime,
      speech: speech,
      voice: voice,
      whisperFiles: whisperFiles,
      httpClient: _models,
      // Every name is on the public web: tests never ask real DNS.
      resolve: (_) async => [InternetAddress('93.184.216.34')],
      makeWhisper: (_, microphone) {
        chosenMicrophone = microphone;
        return whisper;
      },
      listMicrophones: () async => microphones,
      readPdf: (bytes) => pdfText(bytes),
      deviceAuth: deviceAuth,
      makeTranscriber: (_) => fileTranscriber,
      decodeAudio: (bytes) => decodeAudio(bytes),
      validate: (spec, key) async {
        await connectHold?.future;
        if (rejected != null) throw rejected!;
        return models;
      },
      makeProvider: (spec, key, {model, planToken, webSearch = false}) {
        searches.add(webSearch);
        created.add((spec.name, key, model));
        tokens.add(planToken);
        return provider;
      },
      today: today,
      exchange: Exchange(
        mobile: mobile,
        share: SharePlus.custom(share),
        scratch: () async => scratch.createTempSync('export'),
      ),
      // A light app-lock hash, worked out right here: tests need no isolates.
      lockIterations: 10,
      offThread: <R>(work) async => work(),
      driveAuth: auth,
      localModels: localModels,
      remoteFor: (_) => remote,
      chatGpt: chatGpt,
      listPlanModels: (token) async {
        await token();
        return planModels;
      },
    );
    if (owned) addTearDown(session.dispose);
    return session;
  }
}

/// A Google sign-in that grants at once (or fails as told).
class FakeAuth implements DriveAuth {
  var granted = false;
  Exception? failSignIn;
  Exception? failToken;
  Exception? failSignOut;
  var signedOut = false;

  /// When set, a sign-in waits for it: the time a browser or a picker takes.
  Completer<void>? hold;

  @override
  Future<bool> signedIn() async => granted;

  @override
  Future<void> signIn() async {
    await hold?.future;
    if (failSignIn case final error?) throw error;
    granted = true;
  }

  @override
  Future<String> token({bool refresh = false}) async {
    if (failToken case final error?) throw error;
    return 'token';
  }

  @override
  Future<void> signOut() async {
    if (failSignOut case final error?) throw error;
    signedOut = true;
    granted = false;
  }
}

/// The sync remote, in memory: text by path, like Drive under Notelore/.
class MemoryRemote implements Remote {
  final texts = <String, String>{};
  Exception? failure;

  /// While set, listing waits for it: a sync that is still running.
  Completer<void>? hold;
  var _next = 0;
  final _ids = <String, String>{};

  RemoteFile _meta(String rel) => RemoteFile(
    id: _ids[rel] ??= 'id${++_next}',
    md5: md5.convert(utf8.encode(texts[rel]!)).toString(),
    modified: '${texts[rel]!.length}',
  );

  @override
  Future<Map<String, RemoteFile>> list() async {
    await hold?.future;
    if (failure case final error?) throw error;
    return {for (final rel in texts.keys) rel: _meta(rel)};
  }

  @override
  Future<List<int>> download(String fileId) async =>
      utf8.encode(texts[_ids.entries.firstWhere((e) => e.value == fileId).key]!);

  @override
  Future<RemoteFile> upload(String rel, List<int> data, String? fileId) async {
    texts[rel] = utf8.decode(data);
    return _meta(rel);
  }

  @override
  Future<void> trash(String fileId) async {
    texts.remove(_ids.entries.firstWhere((e) => e.value == fileId).key);
  }
}

/// url_launcher, recording what it was asked to open.
class FakeLauncher extends UrlLauncherPlatform with MockPlatformInterfaceMixin {
  final opened = <String>[];

  /// How each was opened: the browser app or one inside Notelore.
  final modes = <PreferredLaunchMode>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    modes.add(options.mode);
    return true;
  }
}

/// Hears the scripted phrases in order; null is silence. Then waits until cancelled.
class FakeSpeech implements Speech {
  FakeSpeech(this.phrases);

  /// What each let-go hands back, in order (null: nothing was said).
  final List<String?> phrases;
  final languages = <String>[];
  var cancels = 0;
  var finishes = 0;
  Completer<String?>? _waiting;
  Object? failure;

  @override
  Future<String?> listen(String language) {
    languages.add(language);
    if (failure case final error?) return Future.error(error);
    return (_waiting = Completer<String?>()).future;
  }

  @override
  Future<void> finish() async {
    finishes++;
    _waiting?.complete(phrases.isEmpty ? null : phrases.removeAt(0));
    _waiting = null;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    _waiting?.complete(null);
    _waiting = null;
  }
}

class FakeVoice implements Voice {
  final spoken = <(String, String)>[];
  var stops = 0;

  /// While set, speaking lasts until it completes (or [stop]).
  Completer<void>? holding;

  @override
  Future<void> speak(String text, String language) async {
    spoken.add((text, language));
    await holding?.future;
  }

  @override
  Future<void> stop() async => stops++;
}

/// The device's lock: there unless [hasLock] is false; each ask takes the
/// next of [answers] (yes when none is left) and records its reason.
class FakeDeviceAuth implements DeviceAuth {
  var hasLock = true;
  final answers = <bool>[];
  final reasons = <String>[];

  @override
  Future<bool> available() async => hasLock;

  @override
  Future<bool> authenticate(String reason) async {
    reasons.add(reason);
    return answers.isEmpty ? true : answers.removeAt(0);
  }
}

/// The share sheet: records what it was handed, answers as told.
class FakeShare extends SharePlatform with MockPlatformInterfaceMixin {
  final shared = <ShareParams>[];

  /// What each shared file held when it was handed over, by name.
  final contents = <String, List<int>>{};
  var status = ShareResultStatus.success;

  @override
  Future<ShareResult> share(ShareParams params) async {
    shared.add(params);
    for (final file in params.files ?? const <XFile>[]) {
      contents[file.name] = await file.readAsBytes();
    }
    return ShareResult('', status);
  }
}

/// Open and save dialogs: answer with what a test sets, record what was asked.
class FakeFileSelector extends FileSelectorPlatform with MockPlatformInterfaceMixin {
  /// Picked by the open dialog; none means it was called off.
  var picked = <XFile>[];

  /// When set, the open dialog stays up until it completes.
  Completer<void>? hold;
  String? saveAt;
  String? folder;
  final suggested = <String?>[];
  final groups = <List<XTypeGroup>?>[];

  @override
  Future<List<XFile>> openFiles({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    groups.add(acceptedTypeGroups);
    await hold?.future;
    return picked;
  }

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    suggested.add(options.suggestedName);
    return saveAt == null ? null : FileSaveLocation(saveAt!);
  }

  @override
  Future<String?> getDirectoryPath({String? initialDirectory, String? confirmButtonText}) async =>
      folder;
}

/// The app kept out of the system's freezer (#409): what was asked, in order.
/// A device's notifications: what is pending, by id, and what was asked.
class FakeReminders implements ReminderNotifier {
  final pending = <int, String>{};
  final scheduled = <DueReminder>[];
  final cancelled = <int>[];
  var allowed = true;

  /// What the user answers when asked.
  var grant = false;
  var asked = 0;

  /// Thrown by every call, like a platform that cannot notify.
  Exception? fail;

  void _check() {
    if (fail case final error?) throw error;
  }

  @override
  Future<bool> isAllowed() async {
    _check();
    return allowed;
  }

  @override
  Future<bool> ask() async {
    _check();
    asked++;
    return allowed = grant;
  }

  @override
  Future<Set<int>> ids() async {
    _check();
    return pending.keys.toSet();
  }

  @override
  Future<void> schedule(DueReminder reminder) async {
    _check();
    scheduled.add(reminder);
    pending[reminder.id] = reminder.text;
  }

  @override
  Future<void> cancel(int id) async {
    _check();
    cancelled.add(id);
    pending.remove(id);
  }
}

class FakeAwake implements Awake {
  final calls = <String>[];

  @override
  Future<void> hold() async => calls.add('hold');

  @override
  Future<void> release() async => calls.add('release');
}

/// Whisper over an attached file: [answers] in order, what it heard recorded.
class FakeTranscriber implements Transcriber {
  final answers = <String>[];
  final heard = <int>[];

  /// When set, hearing waits for it: a long recording.
  Completer<void>? hold;

  @override
  Future<String> transcribe(Float32List samples, String language) async {
    heard.add(samples.length);
    await hold?.future;
    return answers.isEmpty ? '' : answers.removeAt(0);
  }
}
