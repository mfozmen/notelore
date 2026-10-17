/// The app lock's PIN or password, kept only as a salted, slow hash.
///
/// [hashSecret] gives one string, `pbkdf2-sha256$<iterations>$<salt>$<hash>`
/// (salt and hash in base64), for the platform keystore. The secret itself is
/// never stored, and the hash never goes near the notes folder or Drive.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// PBKDF2 rounds for a new hash; a stored hash keeps the count it was made with.
const defaultIterations = 120000;

const _scheme = 'pbkdf2-sha256';

/// The stored form of [secret], with a fresh 16-byte salt from [random].
String hashSecret(String secret, {int iterations = defaultIterations, Random? random}) {
  final source = random ?? Random.secure();
  final salt = List<int>.generate(16, (_) => source.nextInt(256));
  final hash = pbkdf2(_bytes(secret), salt, iterations, 32);
  return [_scheme, iterations, base64.encode(salt), base64.encode(hash)].join(r'$');
}

/// Whether [secret] is the one [stored] was made from; false for anything damaged.
bool verifySecret(String secret, String stored) {
  final parts = stored.split(r'$');
  if (parts.length != 4 || parts[0] != _scheme) return false;
  final iterations = int.tryParse(parts[1]) ?? 0;
  if (iterations < 1) return false;
  final List<int> salt, expected;
  try {
    salt = base64.decode(parts[2]);
    expected = base64.decode(parts[3]);
  } on FormatException {
    return false;
  }
  if (expected.isEmpty) return false;
  final actual = pbkdf2(_bytes(secret), salt, iterations, expected.length);
  // Constant time: every byte is compared, whatever the first difference.
  var difference = 0;
  for (var i = 0; i < expected.length; i++) {
    difference |= expected[i] ^ actual[i];
  }
  return difference == 0;
}

/// PBKDF2 with HMAC-SHA256 (RFC 8018), [length] bytes.
Uint8List pbkdf2(List<int> password, List<int> salt, int iterations, int length) {
  final mac = Hmac(sha256, password);
  final out = BytesBuilder(copy: false);
  for (var block = 1; out.length < length; block++) {
    var u = mac.convert([
      ...salt,
      block >> 24 & 0xff,
      block >> 16 & 0xff,
      block >> 8 & 0xff,
      block & 0xff,
    ]).bytes;
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = mac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    out.add(t);
  }
  return out.takeBytes().sublist(0, length);
}

/// NFC first: macOS may hand back NFD for the same typed password.
List<int> _bytes(String secret) => utf8.encode(unorm.nfc(secret));
