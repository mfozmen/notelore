import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:notelore_core/src/meaning.dart';
import 'package:notelore_core/src/store/index.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/files.dart';

const _pieces = [
  ['<s>', 0.0],
  ['<pad>', 0.0],
  ['</s>', 0.0],
  ['<unk>', 0.0],
  ['▁', -2.0],
  ['▁hello', -1.0],
  ['▁he', -3.0],
  ['llo', -3.0],
  ['▁world', -1.5],
  ['▁wor', -4.0],
  ['o', -5.0],
  ['l', -5.0],
  ['d', -5.0],
];

String _tokenizerJson() => jsonEncode({
  'model': {'type': 'Unigram', 'unk_id': 3, 'vocab': _pieces},
});

String _note(String title, String body) =>
    '---\ntitle: $title\nkind: topic\ncreated: 2026-09-01\nupdated: 2026-09-01\ntags: []\n---\n'
    '# $title\n\n## Notes\n- 2026-09-01: $body\n';

void main() {
  group('Unigram', () {
    final tokenizer = Unigram.fromJson(_tokenizerJson());

    test('splits words on spaces, each piece starting with ▁, between <s> and </s>', () {
      expect(tokenizer.encode('hello world'), [0, 5, 8, 2]);
      expect(tokenizer.encode(''), [0, 2]);
    });

    test('takes the pieces with the best total score', () {
      // ▁hello + o beats ▁he + llo + o.
      expect(tokenizer.encode('helloo'), [0, 5, 10, 2]);
      // ▁world beats ▁wor + l + d.
      expect(tokenizer.encode('world'), [0, 8, 2]);
    });

    test('characters it has no piece for are one unknown token', () {
      expect(tokenizer.encode('hello xyz'), [0, 5, 4, 3, 2]);
      expect(tokenizer.encode('lxyzl'), [0, 4, 11, 3, 11, 2]);
    });

    test('normalizes width, tabs, control characters and runs of spaces first', () {
      expect(tokenizer.encode('  ｈｅｌｌｏ\t   wor\u0007ld'), [0, 5, 8, 2]);
      // As SentencePiece does, a space at the end is a piece of its own.
      expect(tokenizer.encode('hello\n'), [0, 5, 4, 2]);
    });

    test('cuts at the model length, keeping </s>', () {
      expect(tokenizer.encode('hello world hello', max: 3), [0, 5, 2]);
    });
  });

  test('Embedder: e5 prefixes, mean of the token states, unit length', () {
    final seen = <String>[];
    final embedder = Embedder(
      (text) {
        seen.add(text);
        return [0, 1, 2];
      },
      (ids) => Float32List.fromList([
        for (final id in ids) ...[id.toDouble(), 2],
      ]),
      dim: 2,
    );
    final vector = embedder.query('which?');
    // Mean of (0,2), (1,2), (2,2) is (1,2); scaled to length 1.
    expect(vector[0], closeTo(1 / sqrt(5), 1e-6));
    expect(vector[1], closeTo(2 / sqrt(5), 1e-6));
    embedder.passage('a note');
    expect(seen, ['query: which?', 'passage: a note']);
  });

  test('embedPending embeds the notes without a vector, and only those, in batches', () async {
    final root = p.join(tempDir(), 'notes');
    final index = NoteIndex(p.join(tempDir(), 'index.sqlite'), root);
    addTearDown(index.close);
    for (var i = 0; i < 5; i++) {
      File(p.join(root, 'topics', 'n$i.md'))
        ..createSync(recursive: true)
        ..writeAsStringSync(_note('N$i', 'entry $i'));
    }
    index.rebuild();
    final asked = <List<String>>[];
    Future<List<Float32List>> embed(List<String> texts) async {
      asked.add(texts);
      return [
        for (final _ in texts) Float32List.fromList([1, 0]),
      ];
    }

    expect(await embedPending(index, embed, batch: 2), 5);
    expect(asked.map((b) => b.length), [2, 2, 1]);
    // The text without its front matter.
    expect(asked.first.first, startsWith('# N'));
    expect(await embedPending(index, embed), 0);
    File(p.join(root, 'topics', 'n3.md')).writeAsStringSync(_note('N3', 'changed'));
    index
      ..invalidateAll()
      ..rebuild();
    expect(await embedPending(index, embed), 1);
    expect(asked.last.single, contains('changed'));
  });
}
