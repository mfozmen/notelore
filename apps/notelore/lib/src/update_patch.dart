/// Binary patches for a changed-files Windows update (#585): a new file is
/// sent as copies from the old one plus the bytes that changed, not whole.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Block copied from the old file is at least this many bytes; a changed tail
/// shorter than it is sent as bytes in the new file's place.
const _block = 32;

/// A 64-bit rolling hash of a block, base 257. Collisions only cost a compare.
const _base = 257;

const _magic = 'NLP1';
const _insert = 0;
const _copy = 1;

/// A patch (or a decompressed one) larger than this is refused: no update file
/// is anywhere near it, and a corrupt or hostile patch must not exhaust memory.
const _maxPatch = 512 * 1024 * 1024;

class UpdatePatchFailed implements Exception {
  const UpdatePatchFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A patch that turns [oldBytes] into the new file: calls that match the old
/// file become copies, the rest is sent as bytes. The result is zlib-compressed
/// and starts with [_magic] once decompressed.
Uint8List makePatch(List<int> oldBytes, List<int> newBytes) {
  final old = oldBytes is Uint8List ? oldBytes : Uint8List.fromList(oldBytes);
  final next = newBytes is Uint8List ? newBytes : Uint8List.fromList(newBytes);
  final index = <int, List<int>>{};
  for (var offset = 0; offset + _block <= old.length; offset += _block) {
    final hash = _blockHash(old, offset);
    final offsets = index.putIfAbsent(hash, () => []);
    // A repeated block needs only a few candidates; more is work for no gain.
    if (offsets.length < 4) offsets.add(offset);
  }

  final ops = BytesBuilder(copy: false)..add(ascii.encode(_magic));
  var literal = 0;
  var position = 0;
  var hash = next.length >= _block ? _blockHash(next, 0) : 0;
  final power = _power();
  while (position + _block <= next.length) {
    final match = _match(old, next, position, index[hash]);
    if (match < 0) {
      if (position + _block < next.length) {
        hash = (hash - next[position] * power) * _base + next[position + _block];
      }
      position++;
      continue;
    }
    var length = _block;
    while (position + length < next.length &&
        match + length < old.length &&
        next[position + length] == old[match + length]) {
      length++;
    }
    _addInsert(ops, next, literal, position);
    _addCopy(ops, match, length);
    position += length;
    literal = position;
    if (position + _block <= next.length) hash = _blockHash(next, position);
  }
  _addInsert(ops, next, literal, next.length);
  return Uint8List.fromList(ZLibCodec(level: 9).encode(ops.takeBytes()));
}

/// Applies [patch] to [oldBytes], after checking the old and new SHA-256 and
/// the new size. Throws [UpdatePatchFailed] on any mismatch or damaged patch.
Uint8List applyPatch({
  required List<int> oldBytes,
  required List<int> patch,
  required String oldSha256,
  required String newSha256,
  required int newSize,
}) {
  Uint8List raw;
  try {
    raw = Uint8List.fromList(ZLibCodec().decode(patch));
  } on Object {
    throw const UpdatePatchFailed('the patch is damaged');
  }
  if (raw.length < 4 || ascii.decode(raw.sublist(0, 4), allowInvalid: true) != _magic) {
    throw const UpdatePatchFailed('the patch is not a Notelore patch');
  }
  if (newSize <= 0 || newSize > _maxPatch) throw const UpdatePatchFailed('the new size is wrong');
  final old = oldBytes is Uint8List ? oldBytes : Uint8List.fromList(oldBytes);
  if (sha256.convert(old).toString() != oldSha256 || old.isEmpty) {
    throw const UpdatePatchFailed('the file is not the one the patch expects');
  }
  final out = BytesBuilder(copy: false);
  var at = 4;
  while (at < raw.length) {
    final op = raw[at++];
    if (op == _insert) {
      final length = _varint(raw, at);
      at = length.next;
      if (at + length.value > raw.length) throw const UpdatePatchFailed('the patch is truncated');
      out.add(raw.sublist(at, at + length.value));
      at += length.value;
    } else if (op == _copy) {
      final offset = _varint(raw, at);
      final length = _varint(raw, offset.next);
      at = length.next;
      if (offset.value + length.value > old.length) {
        throw const UpdatePatchFailed('the patch copies past the old file');
      }
      out.add(old.sublist(offset.value, offset.value + length.value));
    } else {
      throw const UpdatePatchFailed('the patch has an unknown step');
    }
    if (out.length > newSize) throw const UpdatePatchFailed('the patch is larger than the file');
  }
  final result = out.takeBytes();
  if (result.length != newSize || sha256.convert(result).toString() != newSha256) {
    throw const UpdatePatchFailed('the patched file is not the expected one');
  }
  return result;
}

int _blockHash(Uint8List bytes, int start, {int length = _block}) {
  var hash = 0;
  for (var i = 0; i < length; i++) {
    hash = hash * _base + bytes[start + i];
  }
  return hash;
}

int _power() {
  var power = 1;
  for (var i = 0; i < _block - 1; i++) {
    power *= _base;
  }
  return power;
}

int _match(Uint8List old, Uint8List next, int position, List<int>? offsets) {
  if (offsets == null) return -1;
  for (final offset in offsets) {
    var same = true;
    for (var i = 0; i < _block; i++) {
      if (old[offset + i] != next[position + i]) {
        same = false;
        break;
      }
    }
    if (same) return offset;
  }
  return -1;
}

void _addInsert(BytesBuilder ops, Uint8List next, int from, int to) {
  if (to <= from) return;
  ops.addByte(_insert);
  _addVarint(ops, to - from);
  ops.add(next.sublist(from, to));
}

void _addCopy(BytesBuilder ops, int offset, int length) {
  ops.addByte(_copy);
  _addVarint(ops, offset);
  _addVarint(ops, length);
}

void _addVarint(BytesBuilder ops, int value) {
  if (value < 0) throw ArgumentError.value(value, 'value');
  while (value >= 0x80) {
    ops.addByte((value & 0x7f) | 0x80);
    value >>= 7;
  }
  ops.addByte(value);
}

({int value, int next}) _varint(Uint8List bytes, int at) {
  var value = 0;
  var shift = 0;
  while (true) {
    if (at >= bytes.length || shift > 56) throw const UpdatePatchFailed('the patch is truncated');
    final byte = bytes[at++];
    value |= (byte & 0x7f) << shift;
    if (byte & 0x80 == 0) return (value: value, next: at);
    shift += 7;
  }
}

/// The archive entry name that carries [path]'s patch.
String patchEntry(String path) => '$path.zpatch';
