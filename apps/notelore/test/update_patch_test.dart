import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notelore/src/update_patch.dart';

Uint8List bytes(int length, int seed) =>
    Uint8List.fromList(List.generate(length, (i) => (i * 31 + seed) & 0xff));

String hash(List<int> data) => sha256.convert(data).toString();

void main() {
  test('a patch rebuilds the new file from the old one', () {
    final old = bytes(200 * 1024, 1);
    final next = Uint8List.fromList(old);
    // A changed middle and a changed tail, like a new engine in app.so.
    for (var i = 90 * 1024; i < 95 * 1024; i++) {
      next[i] = (next[i] + 7) & 0xff;
    }
    for (var i = 190 * 1024; i < next.length; i++) {
      next[i] = (next[i] + 3) & 0xff;
    }

    final patch = makePatch(old, next);
    expect(patch.length, lessThan(next.length ~/ 2));
    expect(
      applyPatch(
        oldBytes: old,
        patch: patch,
        oldSha256: hash(old),
        newSha256: hash(next),
        newSize: next.length,
      ),
      next,
    );
  });

  test('a patch is refused for other old bytes', () {
    final old = bytes(4096, 2);
    final next = Uint8List.fromList(old)..[100] = 9;
    final patch = makePatch(old, next);
    final other = Uint8List.fromList(old)..[100] = 8;
    expect(
      () => applyPatch(
        oldBytes: other,
        patch: patch,
        oldSha256: hash(old),
        newSha256: hash(next),
        newSize: next.length,
      ),
      throwsA(isA<UpdatePatchFailed>()),
    );
  });

  test('a truncated patch is refused', () {
    final old = bytes(4096, 3);
    final next = Uint8List.fromList(old)..[100] = 9;
    final patch = makePatch(old, next);
    expect(
      () => applyPatch(
        oldBytes: old,
        patch: patch.sublist(0, patch.length ~/ 2),
        oldSha256: hash(old),
        newSha256: hash(next),
        newSize: next.length,
      ),
      throwsA(isA<UpdatePatchFailed>()),
    );
  });

  test('a patch that produces another file is refused', () {
    final old = bytes(4096, 4);
    final next = Uint8List.fromList(old)..[100] = 9;
    final patch = makePatch(old, next);
    expect(
      () => applyPatch(
        oldBytes: old,
        patch: patch,
        oldSha256: hash(old),
        newSha256: hash(next),
        newSize: next.length + 1,
      ),
      throwsA(isA<UpdatePatchFailed>()),
    );
  });

  test('a damaged patch stream is refused', () {
    final old = bytes(4096, 5);
    final next = Uint8List.fromList(old)..[100] = 9;
    final patch = makePatch(old, next);
    final raw = ZLibCodec().decode(patch);
    final broken = Uint8List.fromList(ZLibCodec().encode(raw.sublist(0, raw.length - 2)));
    expect(
      () => applyPatch(
        oldBytes: old,
        patch: broken,
        oldSha256: hash(old),
        newSha256: hash(next),
        newSize: next.length,
      ),
      throwsA(isA<UpdatePatchFailed>()),
    );
  });

  test('an empty old file is refused', () {
    final next = utf8.encode('new app');
    final patch = makePatch(const <int>[], next);
    expect(
      () => applyPatch(
        oldBytes: const <int>[],
        patch: patch,
        oldSha256: hash(const <int>[]),
        newSha256: hash(next),
        newSize: next.length,
      ),
      throwsA(isA<UpdatePatchFailed>()),
    );
  });
}
