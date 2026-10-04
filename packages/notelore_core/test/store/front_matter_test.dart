import 'dart:convert';
import 'dart:io';

import 'package:notelore_core/src/store/front_matter.dart';
import 'package:test/test.dart';

import '../support/spec.dart';

/// JSON from spec/fixtures/front-matter.json -> the Dart value it stands for.
Object? decode(Object? json) => switch (json) {
  {'date': final String iso} => DateTime.parse('${iso}T00:00:00Z'),
  final List<Object?> list => [for (final item in list) decode(item)],
  _ => json,
};

void main() {
  final golden = File('${specFixtures().parent.path}/front-matter.json').readAsStringSync();
  final cases = (jsonDecode(golden) as List<Object?>).cast<Map<String, Object?>>();

  test('the golden file is there', () => expect(cases, hasLength(91)));

  group('writes exactly what PyYAML writes', () {
    for (final c in cases) {
      test(c['yaml']! as String, () {
        expect(dumpFrontMatter({'k': decode(c['value'])}), c['yaml']);
      });
    }
  });

  group('reads exactly what PyYAML reads', () {
    for (final c in cases) {
      test(c['yaml']! as String, () {
        expect(loadFrontMatter(c['yaml']! as String)['k'], decode(c['loads_as']));
      });
    }
  });

  test('keys keep their order and every key gets a line', () {
    final meta = loadFrontMatter('title: T\nkind: topic\ncreated: 2026-01-02\ntags: [a, b]\n');
    expect(meta.keys, ['title', 'kind', 'created', 'tags']);
    expect(meta['created'], DateTime.utc(2026, 1, 2));
    expect(dumpFrontMatter(meta), 'title: T\nkind: topic\ncreated: 2026-01-02\ntags: [a, b]\n');
  });

  test('block lists, numbers and timestamps read like PyYAML', () {
    final meta = loadFrontMatter(
      'tags:\n- a\n- b\nhex: 0x1F\nbig: 1_000\nsexa: 1:30\noct: 017\nbin: 0b101\n'
      'f: 1.5\ninf: .inf\nnan: .NaN\nat: 2026-09-12 10:30:00\nempty:\n',
    );
    expect(meta['tags'], ['a', 'b']);
    expect(meta['hex'], 31);
    expect(meta['big'], 1000);
    expect(meta['sexa'], 90);
    expect(meta['oct'], 15);
    expect(meta['bin'], 5);
    expect(meta['f'], 1.5);
    expect(meta['inf'], double.infinity);
    expect((meta['nan']! as double).isNaN, isTrue);
    expect(meta['at'], DateTime.utc(2026, 9, 12, 10, 30));
    expect(meta['empty'], isNull);
  });

  test('numbers and timestamps are written like PyYAML', () {
    expect(
      dumpFrontMatter({
        'f': 1.5,
        'whole': 2.0,
        'inf': double.infinity,
        'ninf': double.negativeInfinity,
        'nan': double.nan,
        'at': DateTime.utc(2026, 9, 12, 10, 30),
      }),
      'f: 1.5\nwhole: 2.0\ninf: .inf\nninf: -.inf\nnan: .nan\nat: 2026-09-12 10:30:00\n',
    );
  });

  test('a nested mapping is read, but writing it is refused rather than mangled', () {
    final meta = loadFrontMatter('extra:\n  a: 1\n');
    expect(meta['extra'], {'a': 1});
    expect(() => dumpFrontMatter(meta), throwsUnsupportedError);
    expect(
      () => dumpFrontMatter({
        'k': [<Object?>[]],
      }),
      throwsUnsupportedError,
    );
  });

  test('a document that is not a mapping or not YAML is rejected', () {
    expect(() => loadFrontMatter('- a\n- b\n'), throwsFormatException);
    expect(() => loadFrontMatter('just a scalar\n'), throwsFormatException);
    expect(() => loadFrontMatter('title: [unclosed\n'), throwsFormatException);
    expect(loadFrontMatter(''), isEmpty);
  });
}
