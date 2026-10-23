import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/update_delta.dart';

const hash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Map<String, Object?> ok() => {
  'version': '1.1.0',
  'from': '1.0.0',
  'system': 'windows',
  'archive': 'delta.zip',
  'archive_sha256': hash,
  'files': {'data/app.so': hash, 'notelore.exe': hash},
};

void main() {
  test('a path is relative, plain and has no way out of the app folder', () {
    expect(isSafeUpdatePath('data/app.so'), isTrue);
    expect(isSafeUpdatePath('notelore.exe'), isTrue);
    for (final path in [
      '',
      '/abs',
      r'\abs',
      r'data\app.so',
      'C:/app.so',
      '../app.so',
      'data/../app.so',
      'data//app.so',
      './app.so',
    ]) {
      expect(isSafeUpdatePath(path), isFalse, reason: path);
    }
  });

  test('parses the manifest for this exact upgrade', () {
    final manifest = DeltaManifest.parse(jsonEncode(ok()), current: '1.0.0', system: 'windows');
    expect(manifest.version, '1.1.0');
    expect(manifest.from, '1.0.0');
    expect(manifest.archive, 'delta.zip');
    expect(manifest.files.keys, ['data/app.so', 'notelore.exe']);
    expect(manifest.toJson(), ok());
  });

  test('rejects another from, system, archive or file hash', () {
    for (final (Map<String, Object?> value, Matcher message) in [
      ({...ok(), 'from': '0.9.0'}, contains('not')),
      ({...ok(), 'system': 'macos'}, contains('not')),
      ({...ok(), 'archive': '../delta.zip'}, contains('not a plain')),
      ({...ok(), 'archive': 'delta.txt'}, contains('not a plain')),
      ({...ok(), 'archive_sha256': 'nope'}, contains('SHA-256')),
      (
        {
          ...ok(),
          'files': {'../app.so': hash},
        },
        contains('not safe'),
      ),
      (
        {
          ...ok(),
          'files': {'notelore-updater.exe': hash},
        },
        contains('not safe'),
      ),
      (
        {
          ...ok(),
          'files': {'app.so': 'nope'},
        },
        contains('SHA-256'),
      ),
      ({...ok(), 'files': <String, Object?>{}}, contains('no files')),
    ]) {
      expect(
        () => DeltaManifest.parse(jsonEncode(value), current: '1.0.0', system: 'windows'),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', message)),
        reason: '$value',
      );
    }
  });

  test('a non-object, a missing field or non-JSON is refused', () {
    for (final text in [
      '[]',
      'not json',
      '{}',
      jsonEncode({'version': '1.1.0'}),
    ]) {
      expect(
        () => DeltaManifest.parse(text, current: '1.0.0', system: 'windows'),
        throwsA(isA<FormatException>()),
        reason: text,
      );
    }
  });

  test('names the delta asset from the version it upgrades', () {
    expect(
      deltaName('1.1.0', 'windows-x64', '1.0.0'),
      'notelore-app-1.1.0-windows-x64-delta-1.0.0.json',
    );
  });
}
