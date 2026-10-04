import 'dart:convert';

import 'package:test/test.dart';

import 'support/spec.dart';

void main() {
  final fixtures = fixtureBytes();

  test('the shared fixtures are all there', () {
    expect(fixtures.keys, [
      'mopsos.md',
      'multiline-and-loose-lines.md',
      'simple.crlf.md',
      'turkish.md',
      'unknown-and-empty-sections.md',
    ]);
  });

  test('the CRLF fixture keeps its CRLF on every OS (.gitattributes)', () {
    expect(utf8.decode(fixtures['simple.crlf.md']!), contains('\r\n'));
  });

  test('every other fixture is LF-only UTF-8', () {
    for (final entry in fixtures.entries.where((e) => !e.key.contains('.crlf.'))) {
      expect(utf8.decode(entry.value), isNot(contains('\r')), reason: entry.key);
    }
  });
}
