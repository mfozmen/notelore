import 'dart:convert';
import 'dart:math';

import 'package:notelore_core/src/secret.dart';
import 'package:test/test.dart';

String _pbkdf2(String password, String salt, int iterations, int length) => [
  for (final byte in pbkdf2(utf8.encode(password), utf8.encode(salt), iterations, length))
    byte.toRadixString(16).padLeft(2, '0'),
].join();

void main() {
  test('pbkdf2 matches the reference vectors (RFC 7914, Python hashlib)', () {
    expect(
      _pbkdf2('passwd', 'salt', 1, 32),
      '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc',
    );
    expect(
      _pbkdf2('Password', 'NaCl', 80000, 32),
      '4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56',
    );
    // Longer than one block of SHA-256.
    expect(
      _pbkdf2('password', 'salt', 2, 40),
      'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43830651afcb5c862f',
    );
  });

  test('a stored secret verifies only the same PIN or password', () {
    final stored = hashSecret('2468', iterations: 10);
    expect(stored, startsWith(r'pbkdf2-sha256$10$'));
    expect(stored, isNot(contains('2468'))); // never the secret itself
    expect(verifySecret('2468', stored), isTrue);
    expect(verifySecret('2469', stored), isFalse);
    expect(verifySecret('', stored), isFalse);
  });

  test('every hash has its own salt', () {
    final first = hashSecret('2468', iterations: 10);
    final second = hashSecret('2468', iterations: 10);
    expect(first, isNot(second));
    expect(verifySecret('2468', second), isTrue);
  });

  test('the salt comes from the given random source', () {
    final stored = hashSecret('x', iterations: 1, random: Random(7));
    expect(stored, hashSecret('x', iterations: 1, random: Random(7)));
    expect(stored.split(r'$'), hasLength(4));
  });

  test('a password is compared in NFC, as macOS may hand back NFD', () {
    final stored = hashSecret('şifre', iterations: 10);
    expect(verifySecret('şifre', stored), isTrue); // decomposed ş
    expect(
      _pbkdf2('şifre', 'tuz', 3, 32),
      '0e9b38f6105bd4d4ceb1a4e6500f1c2931801b195f62ebfb40a90cf6ea23bd42',
    );
  });

  test('the default work factor is strong', () {
    expect(defaultIterations, greaterThanOrEqualTo(100000));
  });

  test('a damaged stored value verifies nothing', () {
    for (final damaged in [
      '',
      'plain',
      r'md5$1$a$b',
      r'pbkdf2-sha256$x$AAAA$AAAA',
      r'pbkdf2-sha256$0$AAAA$AAAA',
      r'pbkdf2-sha256$10$***$AAAA',
      r'pbkdf2-sha256$10$AAAA$',
    ]) {
      expect(verifySecret('2468', damaged), isFalse, reason: damaged);
    }
  });
}
