import 'dart:convert';
import 'dart:io';

import 'package:notelore_core/src/sync/merge.dart';
import 'package:test/test.dart';

import '../support/spec.dart';

/// A merge part in the shape spec/tools/generate_merge.py writes for the reference.
Object describe(MergePart part) => switch (part) {
  Clean(:final lines) => lines,
  Conflict(:final base, :final local, :final remote) => {
    'base': base,
    'local': local,
    'remote': remote,
  },
};

void main() {
  final cases = jsonDecode(
    File('${specFixtures().parent.path}/merge.json').readAsStringSync(),
  ) as List<Object?>;

  test('the contract has hand-picked and generated cases', () {
    expect(cases.length, greaterThan(300));
  });

  for (final (index, raw) in cases.indexed) {
    final c = raw! as Map<String, Object?>;
    test('case $index', () {
      final merged = threeWay(c['base']! as String, c['local']! as String, c['remote']! as String);
      expect(jsonDecode(jsonEncode(merged.parts.map(describe).toList())), c['parts']);
    });
  }
}
