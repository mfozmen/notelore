import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/update_delta.dart';
import 'package:notelore/src/update_patch.dart';
import 'package:path/path.dart' as p;

import '../tool/make_delta.dart';

void write(String path, String text) =>
    (File(path)..parent.createSync(recursive: true)).writeAsStringSync(text);

void main() {
  late String root;
  late String old;
  late String next;
  late String out;

  setUp(() {
    final dir = Directory.systemTemp.createTempSync('notelore_make_delta_');
    addTearDown(() => dir.deleteSync(recursive: true));
    root = dir.path;
    old = p.join(root, 'old');
    next = p.join(root, 'new');
    out = p.join(root, 'out');
    for (final folder in [old, next]) {
      write(p.join(folder, 'notelore.exe'), 'same');
      write(p.join(folder, 'notelore-updater.exe'), 'helper');
    }
  });

  test('writes only the changed files and their manifest', () async {
    write(p.join(old, 'data', 'app.so'), 'old app');
    write(p.join(next, 'data', 'app.so'), 'new app');
    write(p.join(old, 'old.dll'), 'gone');

    final delta = (await makeDelta(
      old: old,
      newRoot: next,
      version: '1.1.0',
      from: '1.0.0',
      out: out,
    ))!;

    expect(delta.manifest.files.keys, ['data/app.so']);
    expect(delta.manifest.archiveSha256, hasLength(64));
    final manifest = DeltaManifest.parse(
      File(p.join(out, deltaName('1.1.0', 'windows-x64', '1.0.0'))).readAsStringSync(),
      version: '1.1.0',
      current: '1.0.0',
      system: 'windows',
    );
    expect(manifest.files, delta.manifest.files);
    final zip = ZipDecoder().decodeBytes(delta.archive.readAsBytesSync());
    expect(zip.files.map((f) => f.name), ['data/app.so']);
    expect(zip.files.single.content, utf8.encode('new app'));
  });

  test('a changed helper stays out of the delta; a missing one disables it', () async {
    write(p.join(old, 'data', 'app.so'), 'old');
    write(p.join(next, 'data', 'app.so'), 'new');
    write(p.join(next, 'notelore-updater.exe'), 'new helper');
    final delta = await makeDelta(
      old: old,
      newRoot: next,
      version: '1.1.0',
      from: '1.0.0',
      out: out,
    );
    expect(delta, isNotNull);
    expect(delta!.manifest.files.keys, ['data/app.so']);

    File(p.join(old, 'notelore-updater.exe')).deleteSync();
    expect(
      await makeDelta(old: old, newRoot: next, version: '1.1.0', from: '1.0.0', out: out),
      isNull,
    );
  });

  test('a large changed file travels as a binary patch (#585)', () async {
    final before = List.generate(200 * 1024, (i) => i & 0xff);
    final after = [...before];
    for (var i = 100 * 1024; i < 102 * 1024; i++) {
      after[i] = (after[i] + 5) & 0xff;
    }
    File(p.join(old, 'data', 'app.so'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(before);
    File(p.join(next, 'data', 'app.so'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(after);

    final delta = (await makeDelta(
      old: old,
      newRoot: next,
      version: '1.1.0',
      from: '1.0.0',
      out: out,
    ))!;

    final patch = delta.manifest.patches['data/app.so']!;
    expect(patch.size, after.length);
    final zip = ZipDecoder().decodeBytes(delta.archive.readAsBytesSync());
    expect(zip.files.map((f) => f.name), [patch.patch]);
    expect(
      applyPatch(
        oldBytes: before,
        patch: zip.files.single.content as List<int>,
        oldSha256: patch.oldSha256,
        newSha256: delta.manifest.files['data/app.so']!,
        newSize: patch.size,
      ),
      after,
    );
  });

  test('no delta when nothing changed', () async {
    expect(
      await makeDelta(old: old, newRoot: next, version: '1.1.0', from: '1.0.0', out: out),
      isNull,
    );
  });
}
