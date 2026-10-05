import 'dart:io';

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
  Harness({List<Object> answers = const [], this.rejected}) {
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
  final created = <(String, String?, String?)>[];

  Session session() {
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
    );
    addTearDown(session.dispose);
    return session;
  }
}
