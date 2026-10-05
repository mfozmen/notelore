import 'dart:convert';
import 'dart:io';

import 'package:notelore_core/src/sync/manifest.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../support/files.dart';

const entry = ManifestEntry(
  localHash: 'h1',
  driveId: 'd1',
  md5: 'm1',
  modified: '2026-10-01T10:00:00Z',
);

void main() {
  late String state;
  setUp(() => state = tempDir());

  String manifestFile() => p.join(state, 'sync', 'manifest.json');

  test('contentHash is NFC and line-ending stable', () {
    const nfc = 'Şükrü\n';
    expect(contentHash(nfc), contentHash(unorm.nfd(nfc)));
    expect(contentHash('a\n'), isNot(contentHash('a\r\n'))); // LF on disk; CRLF is a change
    expect(contentHash(''), hasLength(64));
  });

  test('record, get, base and forget', () {
    final manifest = Manifest(state);
    expect(manifest.get('projects/mopsos.md'), isNull);
    expect(manifest.base('projects/mopsos.md'), isNull);
    manifest.record('projects/mopsos.md', entry, '---\ntitle: Şükrü\n---\n');
    expect(manifest.get('projects/mopsos.md'), entry);
    expect(manifest.base('projects/mopsos.md'), '---\ntitle: Şükrü\n---\n');
    expect(manifest.paths(), ['projects/mopsos.md']);
    final baseFile = File(p.join(state, 'sync', 'base', 'projects', 'mopsos.md'));
    expect(baseFile.readAsBytesSync(), utf8.encode('---\ntitle: Şükrü\n---\n'));
    manifest
      ..forget('projects/mopsos.md')
      ..forget('projects/mopsos.md'); // already gone: fine
    expect(manifest.get('projects/mopsos.md'), isNull);
    expect(baseFile.existsSync(), isFalse);
  });

  test('the file is the same JSON the Python reference writes', () {
    Manifest(state)
      ..record('topics/b.md', entry, 'b\n')
      ..record('topics/a.md', entry, 'a\n');
    expect(
      read(manifestFile()),
      '{\n "topics/a.md": {\n  "local_hash": "h1",\n  "drive_id": "d1",\n  "md5": "m1",\n'
      '  "modified": "2026-10-01T10:00:00Z"\n },\n "topics/b.md": {\n  "local_hash": "h1",\n'
      '  "drive_id": "d1",\n  "md5": "m1",\n  "modified": "2026-10-01T10:00:00Z"\n }\n}\n',
    );
  });

  test('it survives a restart', () {
    Manifest(state).record('topics/x.md', entry, 'x\n');
    final again = Manifest(state);
    expect(again.get('topics/x.md'), entry);
    expect(again.base('topics/x.md'), 'x\n');
  });

  test('a corrupt manifest is derived state and starts empty', () {
    Manifest(state).record('topics/x.md', entry, 'x\n');
    File(manifestFile()).writeAsStringSync('{not json');
    expect(Manifest(state).paths(), isEmpty);
    File(manifestFile()).writeAsStringSync('["a list"]');
    expect(Manifest(state).paths(), isEmpty);
    File(manifestFile()).writeAsBytesSync([0xFF, 0xFE]);
    expect(Manifest(state).paths(), isEmpty);
  });

  test('an entry with a missing or damaged base copy has no base', () {
    final manifest = Manifest(state)..record('topics/x.md', entry, 'x\n');
    final baseFile = File(p.join(state, 'sync', 'base', 'topics', 'x.md'))
      ..writeAsBytesSync([0xFF, 0xFE, 0x20]);
    expect(manifest.base('topics/x.md'), isNull);
    baseFile.deleteSync();
    expect(manifest.base('topics/x.md'), isNull);
  });

  test('unsafe or malformed entries are dropped on load', () {
    const good = {'local_hash': 'h', 'drive_id': 'd', 'md5': 'm', 'modified': 't'};
    File(manifestFile())
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'topics/ok.md': good,
          '../escape.md': good,
          'topics/numbers.md': {...good, 'md5': 5},
          'topics/missing.md': {'local_hash': 'h'},
          'topics/extra.md': {...good, 'more': 'x'},
          'topics/scalar.md': 'oops',
        }),
      );
    expect(Manifest(state).paths(), ['topics/ok.md']);
  });

  for (final rel in [
    '../outside.md',
    '/etc/passwd',
    'C:/x.md',
    'topics/../../x.md',
    'topics/./x.md',
    'topics//x.md',
    '',
    r'topics\x.md',
  ]) {
    test('relative paths from Drive cannot escape: ${jsonEncode(rel)}', () {
      final manifest = Manifest(state);
      final unsafe = throwsA(
        isA<ArgumentError>().having((e) => '$e', 'message', contains('relative path')),
      );
      expect(() => manifest.record(rel, entry, 'x\n'), unsafe);
      expect(() => manifest.base(rel), unsafe);
      manifest.record('topics/keep.md', entry, 'k\n');
      final before = File(manifestFile()).readAsBytesSync();
      expect(() => manifest.forget(rel), unsafe);
      expect(File(manifestFile()).readAsBytesSync(), before); // untouched
    });
  }

  test('entries compare by value', () {
    expect(
      entry.hashCode,
      const ManifestEntry(
        localHash: 'h1',
        driveId: 'd1',
        md5: 'm1',
        modified: '2026-10-01T10:00:00Z',
      ).hashCode,
    );
    expect(
      entry,
      isNot(const ManifestEntry(localHash: 'h2', driveId: 'd1', md5: 'm1', modified: '')),
    );
    expect('$entry', contains('d1'));
  });
}
