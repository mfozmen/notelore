import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/meaning_model.dart';
import 'package:notelore/src/session.dart';
import 'package:notelore/src/whisper_model.dart';
import 'package:notelore_core/notelore_core.dart';
import 'package:path/path.dart' as p;

import 'support.dart';

/// Every note near the reading list's vector, the reading list nearest.
class FakeMeaning implements MeaningModel {
  final embedded = <String>[];
  final queries = <String>[];
  Object? failure;

  @override
  Future<List<Float32List>> passages(List<String> texts) async {
    if (failure case final error?) throw error;
    embedded.addAll(texts);
    return [
      for (final t in texts) Float32List.fromList(t.contains('Reading') ? [1, 0] : [0.5, 0.5]),
    ];
  }

  @override
  Future<Float32List> query(String text) async {
    queries.add(text);
    return Float32List.fromList([1, 0]);
  }
}

String _note(String title) =>
    '---\ntitle: $title\nkind: topic\ncreated: 2020-01-01\nupdated: 2020-01-01\ntags: []\n---\n'
    '# $title\n\n## Notes\n- 2020-01-01: something about $title\n';

void main() {
  /// Until the session's background start and embedding are over.
  Future<void> settled(Session session) async {
    for (var i = 0; i < 200; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await session.catchUpMeaning();
  }

  test('once set up, the model comes by itself; every note gets a vector, and the nearest '
      'notes join the prompt (#929)', () async {
    final meaning = FakeMeaning();
    final harness = Harness(answers: ['Added.'])
      ..meaning = meaning
      ..metered = false
      ..modelPage = 'model bytes'
      ..meaningFiles = [
        ModelFile(
          'e5.onnx',
          'https://models.test/e5.onnx',
          sha256.convert(utf8.encode('model bytes')).toString(),
          11,
        ),
      ];
    for (var i = 0; i < 25; i++) {
      File(p.join(harness.paths.notes.path, 'topics', 'n$i.md'))
        ..createSync(recursive: true)
        ..writeAsStringSync(_note('N$i'));
    }
    File(p.join(harness.paths.notes.path, 'topics', 'reading.md'))
        .writeAsStringSync(_note('Reading'));
    final session = harness.session();
    expect(harness.meaningOpened, isEmpty); // not before setup
    await session.connect(findProvider('anthropic'), 'sk-ant-1');
    await settled(session);
    expect(session.meaningModel.ready, isTrue);
    expect(harness.meaningOpened.single, (session.meaningModel.dir, null));
    expect(meaning.embedded, hasLength(26));
    await session.send('Tutunamayanlar');
    expect(meaning.queries, ['Tutunamayanlar']);
    expect(harness.provider.systems.single, contains('- Reading: reading, topic'));
    // A start with the model already here downloads nothing.
    harness.modelPage = null;
    final again = harness.session();
    await again.load();
    await settled(again);
    expect(harness.meaningOpened, hasLength(2));
  });

  test('a note the agent writes gets its vector after the turn', () async {
    final meaning = FakeMeaning();
    final harness = Harness(
      answers: [
        AgentResponse([
          {
            'type': 'tool_use',
            'id': 't1',
            'name': 'create_note',
            'input': {'kind': 'project', 'title': 'Reading'},
          },
        ], 'tool_use'),
        'Made it.',
        'Made it, nothing to add yet.',
      ],
    )..meaning = meaning;
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'sk-ant-1');
    await settled(session);
    expect(meaning.embedded, isEmpty);
    await session.send('Start a reading list');
    await settled(session);
    expect(meaning.embedded.single, startsWith('# Reading'));
  });

  test(
    'on mobile data or an unknown connection it waits; a swapped file is never opened',
    () async {
      final file = ModelFile(
        'e5.onnx',
        'https://models.test/e5.onnx',
        sha256.convert(utf8.encode('model bytes')).toString(),
        11,
      );
      final harness = Harness(answers: ['Hi.'])
        ..meaning = FakeMeaning()
        ..modelPage = 'model bytes'
        ..meaningFiles = [file];
      final session = harness.session();
      await session.connect(findProvider('anthropic'), 'sk-ant-1');
      await settled(session);
      expect(session.meaningModel.ready, isFalse);
      expect(harness.meaningOpened, isEmpty);

      // Here, but not the pinned bytes: deleted, not opened.
      File(session.meaningModel.path('e5.onnx'))
        ..createSync(recursive: true)
        ..writeAsStringSync('other bytes');
      final again = harness.session();
      await again.connect(findProvider('anthropic'), 'sk-ant-1');
      await settled(again);
      expect(harness.meaningOpened, isEmpty);
      expect(File(session.meaningModel.path('e5.onnx')).existsSync(), isFalse);
    },
  );

  test('without the model, or when it fails, the note list follows the words', () async {
    // The download fails: nothing is opened, and the turn still runs.
    final harness = Harness(answers: ['Hi.', 'Hi again.'])
      ..metered = false
      ..meaningFiles = [const ModelFile('e5.onnx', 'https://models.test/e5.onnx', 'x', 11)];
    final session = harness.session();
    await session.connect(findProvider('anthropic'), 'sk-ant-1');
    await settled(session);
    expect(harness.meaningOpened, isEmpty);
    expect(session.meaningModel.ready, isFalse);
    expect(await session.send('hello'), isTrue);

    // Here but failing: embedding stops quietly.
    final failing = FakeMeaning()..failure = StateError('no onnxruntime');
    final broken = Harness(answers: ['Hi.'])..meaning = failing;
    File(p.join(broken.paths.notes.path, 'topics', 'a.md'))
      ..createSync(recursive: true)
      ..writeAsStringSync(_note('A'));
    final second = broken.session();
    await second.connect(findProvider('anthropic'), 'sk-ant-1');
    await settled(second);
    expect(failing.embedded, isEmpty);
    expect(await second.send('hello'), isTrue);
  });
}
