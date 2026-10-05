import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/session.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;

final today = DateTime.utc(2026, 9, 30);

/// Returns the scripted answers in order and records the user messages it saw.
class ScriptedProvider implements LlmProvider {
  ScriptedProvider(this.answers, {this.model = 'scripted'});

  final List<Object> answers; // AgentResponse, String (a text answer) or an Exception
  final asked = <String>[];

  @override
  final String model;

  @override
  Future<AgentResponse> turn(String system, List<Message> messages, List<Tool> tools) async {
    asked.add('${messages.last['content']}');
    final answer = answers.removeAt(0);
    if (answer is Exception) throw answer;
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
  Harness({List<Object> answers = const [], this.rejected, this.auth}) {
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
  final Exception? rejected;
  final FakeAuth? auth;
  final remote = MemoryRemote();
  final created = <(String, String?, String?)>[];

  /// A session the test closes itself; pass [owned] false when an app takes it over.
  Session session({bool owned = true}) {
    final session = Session(
      paths,
      validate: (spec, key) async {
        if (rejected != null) throw rejected!;
      },
      makeProvider: (spec, key, {model}) {
        created.add((spec.name, key, model));
        return provider;
      },
      today: today,
      driveAuth: auth,
      remoteFor: (_) => remote,
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
  var _next = 0;
  final _ids = <String, String>{};

  RemoteFile _meta(String rel) => RemoteFile(
    id: _ids[rel] ??= 'id${++_next}',
    md5: md5.convert(utf8.encode(texts[rel]!)).toString(),
    modified: '${texts[rel]!.length}',
  );

  @override
  Future<Map<String, RemoteFile>> list() async {
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
