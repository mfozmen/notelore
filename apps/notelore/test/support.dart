import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notelore/src/session.dart';
import 'package:notelore/src/voice.dart';
import 'package:notelore/src/whisper_model.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

final today = DateTime.utc(2026, 9, 30);

/// Returns the scripted answers in order and records the user messages it saw.
class ScriptedProvider implements LlmProvider {
  ScriptedProvider(this.answers, {this.model = 'scripted'});

  // AgentResponse, String (a text answer), an Exception, or a Future (e.g. one never answered)
  final List<Object> answers;
  final asked = <String>[];

  /// How many messages of history each turn carried.
  final lengths = <int>[];

  @override
  final String model;

  @override
  Future<AgentResponse> turn(String system, List<Message> messages, List<Tool> tools) async {
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

/// Everything a session test needs: temp folders, an empty keystore and a
/// provider that answers from [answers]. Validation passes unless [rejected].
class Harness {
  Harness({
    List<Object> answers = const [],
    this.rejected,
    this.auth,
    this.chatGpt,
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
  }

  late final NotelorePaths paths;
  late final ScriptedProvider provider;

  /// When set, the provider refuses the key (tests may set it after connecting).
  Exception? rejected;

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

  /// Voice mode's ears and mouth: nothing heard unless a test scripts it.
  final speech = FakeSpeech([]);
  final voice = FakeVoice();

  /// Whisper's speech, and the one small model file it downloads (absent: 404).
  final whisper = FakeSpeech([]);
  String? modelPage = 'whisper bytes';
  static final whisperFiles = [
    ModelFile(
      'w.onnx',
      'https://models.test/w.onnx',
      sha256.convert(utf8.encode('whisper bytes')).toString(),
      13,
    ),
  ];
  http.Client _models() => MockClient((request) async {
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
  }) {
    final session = Session(
      paths,
      systemLanguage: systemLanguage,
      keySpace: keySpace,
      clock: clock,
      speech: speech,
      voice: voice,
      whisperFiles: whisperFiles,
      httpClient: _models,
      makeWhisper: (_) => whisper,
      validate: (spec, key) async {
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
      driveAuth: auth,
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
  var signedOut = false;

  @override
  Future<bool> signedIn() async => granted;

  @override
  Future<void> signIn() async {
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

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    return true;
  }
}

/// Hears the scripted phrases in order; null is silence. Then waits until cancelled.
class FakeSpeech implements Speech {
  FakeSpeech(this.phrases);

  final List<String?> phrases;
  final languages = <String>[];
  var cancels = 0;
  Completer<String?>? _waiting;
  Object? failure;

  @override
  Future<String?> listen(String language) {
    languages.add(language);
    if (failure case final error?) return Future.error(error);
    if (phrases.isNotEmpty) return Future.value(phrases.removeAt(0));
    return (_waiting = Completer<String?>()).future;
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

  @override
  Future<void> speak(String text, String language) async => spoken.add((text, language));

  @override
  Future<void> stop() async => stops++;
}
